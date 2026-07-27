/********************************************************************************
JIRA NUMBER: RIB-183899 
JIRA SUMMARY: RIB-182739 : Section 71109 - SSI population - Notice to Impacted Population
DESCRIPTION: 
DEVELOPER : rjohri
IMPACTED TABLES:
A. IES:CO_MASS_MAILING_REQ
REVISION HISTORY:
23/06/2026- CREATED
CO_REQUEST_HISTORY
********************************************************************************/
ALTER SESSION SET current_schema = ie_app_online;

SET SERVEROUTPUT ON;

SET TIMING ON;
SET DEFINE OFF;

--------------------------------------------------------------------------------
-- Ensure multilingual notice text columns support content larger than 4,000 bytes.
--------------------------------------------------------------------------------
ALTER TABLE IE_APP_ONLINE.CO_MASS_MAILING_REQ
    MODIFY NOTICE_TXT CLOB;

ALTER TABLE IE_APP_ONLINE.CO_MASS_MAILING_REQ
    MODIFY NOTICE_TEXT_ES CLOB;

ALTER TABLE IE_APP_ONLINE.CO_MASS_MAILING_REQ
    MODIFY NOTICE_TEXT_PT CLOB;

DECLARE
    cnt NUMBER;
BEGIN
    SELECT
        COUNT(1)
    INTO cnt
    FROM
        all_tables
    WHERE
            table_name = 'TRIGGER_INFO_183899'
        AND owner = 'BKUP_TABLES';

    IF cnt = 0 THEN
        EXECUTE IMMEDIATE 'CREATE TABLE BKUP_TABLES.TRIGGER_INFO_183899(CASE_NUM NUMBER, INDV_ID NUMBER, TOA VARCHAR2(5), NOTICE_TRIGGERED CHAR(1), NOTICE_TRIGGERED_DT DATE, SMS_TRIGGERED CHAR(1), SMS_TRIGGERED_DT DATE, EMAIL_TRIGGERED CHAR(1), EMAIL_TRIGGERED_DT DATE) ';
    END IF;
END;
/

DECLARE
    cnt NUMBER;
BEGIN
    SELECT
        COUNT(1)
    INTO cnt
    FROM
        all_tables
    WHERE
            table_name = 'MN_IMP_POPULATION_183899'
        AND owner = 'BKUP_TABLES';

    IF cnt = 0 THEN
        EXECUTE IMMEDIATE 'CREATE TABLE BKUP_TABLES.MN_IMP_POPULATION_183899(CASE_NUM NUMBER, INDV_ID NUMBER, TOA VARCHAR2(5), NOTICE_TRIGGERED CHAR(1), NOTICE_TRIGGERED_DT DATE) ';
    END IF;
END;
/
/*
--This table will store overall trigger information from DFs 183899, 183903, 183905
INSERT INTO BKUP_TABLES.TRIGGER_INFO_183899 (CASE_NUM, INDV_ID, TOA, NOTICE_TRIGGERED,EMAIL_TRIGGERED, SMS_TRIGGERED)
SELECT CASE_NUM, INDV_ID, TOA, 'N' NOTICE_TRIGGERED, 'N' EMAIL_TRIGGERED, 'N' SMS_TRIGGERED
FROM 
BKUP_TABLES.IMPACTED_POPULATION_182739 B 
WHERE NOT EXISTS(SELECT 1 FROM BKUP_TABLES.TRIGGER_INFO_183899 B1 WHERE B1.CASE_NUM = B.CASE_NUM AND B.INDV_ID = B1.INDV_ID); --to avoid duplicate insertion

--This table will store manual notice trigger information
INSERT INTO BKUP_TABLES.MN_IMP_POPULATION_183899 (CASE_NUM, INDV_ID, TOA, NOTICE_TRIGGERED)
SELECT CASE_NUM, INDV_ID, TOA, 'N' NOTICE_TRIGGERED
FROM 
BKUP_TABLES.IMPACTED_POPULATION_182739 B 
WHERE NOT EXISTS(SELECT 1 FROM BKUP_TABLES.MN_IMP_POPULATION_183899 B1 WHERE B1.CASE_NUM = B.CASE_NUM AND B.INDV_ID = B1.INDV_ID); --to avoid duplicate insertion
	*/		

--------------------------------------------------------------------------------
-- Populate trigger backup table using the revised impacted population.
--------------------------------------------------------------------------------
DECLARE        
    tot_ct     PLS_INTEGER := 0;
    tot_cn_ct  PLS_INTEGER := 0;
BEGIN  
INSERT INTO BKUP_TABLES.TRIGGER_INFO_183899
(
    CASE_NUM,
    INDV_ID,
    TOA,
    NOTICE_TRIGGERED,
    EMAIL_TRIGGERED,
    SMS_TRIGGERED
)
WITH params AS
(
    SELECT DATE '2026-10-01' AS as_of_dt
      FROM dual
),
preg_indv AS
(
    SELECT /*+ PARALLEL(4) */
           p.indv_id
      FROM ie_app_online.dc_pregnancies p
      CROSS JOIN params prm
     WHERE prm.as_of_dt > p.eff_begin_dt
       AND
       (
           p.eff_end_dt IS NULL
           OR p.eff_end_dt > prm.as_of_dt
       )
       AND
       (
           (
               p.termination_dt IS NOT NULL
               AND p.termination_dt >= prm.as_of_dt
           )
           OR
           (
               p.due_dt IS NOT NULL
               AND p.due_dt >= prm.as_of_dt
           )
       )
),
postpartum_indiv AS
(
    SELECT /*+ PARALLEL(4) */
           p.indv_id
      FROM ie_app_online.dc_pregnancies p
      CROSS JOIN params prm
     WHERE
           (
               p.termination_dt IS NOT NULL
               OR p.due_dt IS NOT NULL
           )
       AND NVL(p.termination_dt, p.due_dt) <= prm.as_of_dt
       AND NVL(p.termination_dt, p.due_dt) >= ADD_MONTHS(prm.as_of_dt, -12)
),
excluded_indv AS
(
    SELECT DISTINCT indv_id
      FROM preg_indv

    UNION

    SELECT DISTINCT indv_id
      FROM postpartum_indiv
),
base_rows AS
(
    SELECT /*+ PARALLEL(16) */
           b.indv_id,
           a.case_num,
           a.edg_trace_id,
           a.type_of_assistance_cd,
           a.edbc_run_dt,
           c.ssn,
           dp.us_citizen_sw,
           TRUNC
           (
               MONTHS_BETWEEN(prm.as_of_dt, c.dob_dt) / 12
           ) AS age_in_years,
           d.read_lang_cd
      FROM params prm
      JOIN ie_app_online.dc_cases d
        ON 1 = 1
      JOIN ie_app_online.ed_eligibility a
        ON a.case_num = d.case_num
      JOIN ie_app_online.ed_indv_eligibility b
        ON a.case_num = b.case_num
       AND a.edg_trace_id = b.edg_trace_id
      JOIN ie_app_online.dc_indv c
        ON b.indv_id = c.indv_id
      LEFT JOIN ie_app_online.dc_demographics dp
        ON c.indv_id = dp.indv_id
       AND dp.eff_end_dt IS NULL
     WHERE a.type_of_assistance_cd = 'TP13'
       AND b.target_sw = 'Y'
       AND a.payment_end_dt IS NULL
       AND a.cg_status_cd = 'AP'
       AND a.current_elig_ind = 'A'
       AND NOT EXISTS
           (
               SELECT 1
                 FROM excluded_indv x
                WHERE x.indv_id = b.indv_id
           )
),
latest_sdx AS
(
    SELECT y.ssn,
           y.alien_ind_cd
      FROM
      (
          SELECT d.ssn,
                 d.alien_ind_cd,
                 ROW_NUMBER() OVER
                 (
                     PARTITION BY d.ssn
                     ORDER BY d.sdx_seq_num DESC
                 ) AS rn
            FROM ie_app_online.in_sdx d
            JOIN
            (
                SELECT DISTINCT ssn
                  FROM base_rows
            ) s
              ON s.ssn = d.ssn
      ) y
     WHERE y.rn = 1
       AND
       (
           y.alien_ind_cd NOT IN
           (
               'A',
               'B',
               'C',
               'R',
               'Q',
               'K',
               'N',
               'S',
               'X',
               'E',
               'P'
           )
           OR y.alien_ind_cd IS NULL
       )
),
sm AS
(
    SELECT i.indv_id,
           MAX
           (
               CASE
                   WHEN e.type_of_assistance_cd = 'SSPC'
                   THEN 'Y'
               END
           ) AS sspc_eligible,
           MAX
           (
               CASE
                   WHEN e.program_cd = 'MC'
                   THEN 'Y'
               END
           ) AS mc_eligible
      FROM ie_app_online.ed_eligibility e
      JOIN ie_app_online.ed_indv_eligibility i
        ON e.case_num = i.case_num
       AND e.edg_trace_id = i.edg_trace_id
      JOIN
      (
          SELECT DISTINCT
                 indv_id,
                 case_num
            FROM base_rows
      ) br
        ON br.indv_id = i.indv_id
       AND br.case_num = i.case_num
     WHERE e.current_elig_ind = 'A'
       AND e.cg_status_cd IN ('AP', 'CE')
       AND i.target_sw = 'Y'
       AND e.payment_end_dt IS NULL
       AND
       (
           e.type_of_assistance_cd = 'SSPC'
           OR e.program_cd = 'MC'
       )
       AND e.delete_sw = 'N'
     GROUP BY i.indv_id
),
impacted_population AS
(
    SELECT DISTINCT
           b.indv_id,
           b.case_num,
           b.type_of_assistance_cd AS toa,
           d.alien_ind_cd,
           NVL(sm.sspc_eligible, 'N') AS sspc_eligible,
           NVL(sm.mc_eligible, 'N') AS mc_eligible,
           rt.description AS language_description
      FROM base_rows b
      JOIN latest_sdx d
        ON d.ssn = b.ssn
      LEFT JOIN sm
        ON sm.indv_id = b.indv_id
      LEFT JOIN ie_app_online.rt_language_mv rt
        ON rt.code = b.read_lang_cd
     WHERE
           (
               d.alien_ind_cd NOT IN
               (
                   'A',
                   'B',
                   'C',
                   'R',
                   'Q',
                   'K',
                   'N',
                   'S',
                   'X',
                   'E',
                   'P'
               )
               OR
               (
                   d.alien_ind_cd IS NULL
                   AND b.us_citizen_sw = 'N'
               )
           )
       AND b.age_in_years > 19
)
SELECT p.case_num,
       p.indv_id,
       p.toa,
       'N' AS notice_triggered,
       'N' AS email_triggered,
       'N' AS sms_triggered
  FROM impacted_population p
 WHERE NOT EXISTS
       (
           SELECT 1
             FROM BKUP_TABLES.TRIGGER_INFO_183899 b1
            WHERE b1.case_num = p.case_num
              AND b1.indv_id = p.indv_id
       );

--------------------------------------------------------------------------------
-- Populate manual-notice backup table using the same revised population.
--------------------------------------------------------------------------------

INSERT INTO BKUP_TABLES.MN_IMP_POPULATION_183899
(
    CASE_NUM,
    INDV_ID,
    TOA,
    NOTICE_TRIGGERED
)
WITH params AS
(
    SELECT DATE '2026-10-01' AS as_of_dt
      FROM dual
),
preg_indv AS
(
    SELECT /*+ PARALLEL(4) */
           p.indv_id
      FROM ie_app_online.dc_pregnancies p
      CROSS JOIN params prm
     WHERE prm.as_of_dt > p.eff_begin_dt
       AND
       (
           p.eff_end_dt IS NULL
           OR p.eff_end_dt > prm.as_of_dt
       )
       AND
       (
           (
               p.termination_dt IS NOT NULL
               AND p.termination_dt >= prm.as_of_dt
           )
           OR
           (
               p.due_dt IS NOT NULL
               AND p.due_dt >= prm.as_of_dt
           )
       )
),
postpartum_indiv AS
(
    SELECT /*+ PARALLEL(4) */
           p.indv_id
      FROM ie_app_online.dc_pregnancies p
      CROSS JOIN params prm
     WHERE
           (
               p.termination_dt IS NOT NULL
               OR p.due_dt IS NOT NULL
           )
       AND NVL(p.termination_dt, p.due_dt) <= prm.as_of_dt
       AND NVL(p.termination_dt, p.due_dt) >= ADD_MONTHS(prm.as_of_dt, -12)
),
excluded_indv AS
(
    SELECT DISTINCT indv_id
      FROM preg_indv

    UNION

    SELECT DISTINCT indv_id
      FROM postpartum_indiv
),
base_rows AS
(
    SELECT /*+ PARALLEL(16) */
           b.indv_id,
           a.case_num,
           a.edg_trace_id,
           a.type_of_assistance_cd,
           a.edbc_run_dt,
           c.ssn,
           dp.us_citizen_sw,
           TRUNC
           (
               MONTHS_BETWEEN(prm.as_of_dt, c.dob_dt) / 12
           ) AS age_in_years,
           d.read_lang_cd
      FROM params prm
      JOIN ie_app_online.dc_cases d
        ON 1 = 1
      JOIN ie_app_online.ed_eligibility a
        ON a.case_num = d.case_num
      JOIN ie_app_online.ed_indv_eligibility b
        ON a.case_num = b.case_num
       AND a.edg_trace_id = b.edg_trace_id
      JOIN ie_app_online.dc_indv c
        ON b.indv_id = c.indv_id
      LEFT JOIN ie_app_online.dc_demographics dp
        ON c.indv_id = dp.indv_id
       AND dp.eff_end_dt IS NULL
     WHERE a.type_of_assistance_cd = 'TP13'
       AND b.target_sw = 'Y'
       AND a.payment_end_dt IS NULL
       AND a.cg_status_cd = 'AP'
       AND a.current_elig_ind = 'A'
       AND NOT EXISTS
           (
               SELECT 1
                 FROM excluded_indv x
                WHERE x.indv_id = b.indv_id
           )
),
latest_sdx AS
(
    SELECT y.ssn,
           y.alien_ind_cd
      FROM
      (
          SELECT d.ssn,
                 d.alien_ind_cd,
                 ROW_NUMBER() OVER
                 (
                     PARTITION BY d.ssn
                     ORDER BY d.sdx_seq_num DESC
                 ) AS rn
            FROM ie_app_online.in_sdx d
            JOIN
            (
                SELECT DISTINCT ssn
                  FROM base_rows
            ) s
              ON s.ssn = d.ssn
      ) y
     WHERE y.rn = 1
       AND
       (
           y.alien_ind_cd NOT IN
           (
               'A',
               'B',
               'C',
               'R',
               'Q',
               'K',
               'N',
               'S',
               'X',
               'E',
               'P'
           )
           OR y.alien_ind_cd IS NULL
       )
),
sm AS
(
    SELECT i.indv_id,
           MAX
           (
               CASE
                   WHEN e.type_of_assistance_cd = 'SSPC'
                   THEN 'Y'
               END
           ) AS sspc_eligible,
           MAX
           (
               CASE
                   WHEN e.program_cd = 'MC'
                   THEN 'Y'
               END
           ) AS mc_eligible
      FROM ie_app_online.ed_eligibility e
      JOIN ie_app_online.ed_indv_eligibility i
        ON e.case_num = i.case_num
       AND e.edg_trace_id = i.edg_trace_id
      JOIN
      (
          SELECT DISTINCT
                 indv_id,
                 case_num
            FROM base_rows
      ) br
        ON br.indv_id = i.indv_id
       AND br.case_num = i.case_num
     WHERE e.current_elig_ind = 'A'
       AND e.cg_status_cd IN ('AP', 'CE')
       AND i.target_sw = 'Y'
       AND e.payment_end_dt IS NULL
       AND
       (
           e.type_of_assistance_cd = 'SSPC'
           OR e.program_cd = 'MC'
       )
       AND e.delete_sw = 'N'
     GROUP BY i.indv_id
),
impacted_population AS
(
    SELECT DISTINCT
           b.indv_id,
           b.case_num,
           b.type_of_assistance_cd AS toa,
           d.alien_ind_cd,
           NVL(sm.sspc_eligible, 'N') AS sspc_eligible,
           NVL(sm.mc_eligible, 'N') AS mc_eligible,
           rt.description AS language_description
      FROM base_rows b
      JOIN latest_sdx d
        ON d.ssn = b.ssn
      LEFT JOIN sm
        ON sm.indv_id = b.indv_id
      LEFT JOIN ie_app_online.rt_language_mv rt
        ON rt.code = b.read_lang_cd
     WHERE
           (
               d.alien_ind_cd NOT IN
               (
                   'A',
                   'B',
                   'C',
                   'R',
                   'Q',
                   'K',
                   'N',
                   'S',
                   'X',
                   'E',
                   'P'
               )
               OR
               (
                   d.alien_ind_cd IS NULL
                   AND b.us_citizen_sw = 'N'
               )
           )
       AND b.age_in_years > 19
)
SELECT p.case_num,
       p.indv_id,
       p.toa,
       'N' AS notice_triggered
  FROM impacted_population p
 WHERE NOT EXISTS
       (
           SELECT 1
             FROM BKUP_TABLES.MN_IMP_POPULATION_183899 b1
            WHERE b1.case_num = p.case_num
              AND b1.indv_id = p.indv_id
       );



/*---------------------------------------Insert Manual Notice ------------------------------*/

FOR I IN (
select distinct case_num from BKUP_TABLES.MN_IMP_POPULATION_183899 where NVL(NOTICE_TRIGGERED,'N') = 'N'
)						   
LOOP

INSERT INTO CO_MASS_MAILING_REQ (MASS_MAILING_SEQ_NUM, MASS_MAILING_ID, NOTICE_TITLE, NOTICE_TXT, LEGAL_CITES, STD_TEXT_LST, PROGRAM_LST, SCHD_DT, AUTHOR, JOB_PROCESSED_SW, CREATE_USER_ID, CREATE_DT, UNIQUE_TRANS_ID, ARCHIVE_DT, HISTORY_SEQ, CASE_NUM_LIST, NOTICE_TITLE_ES, NOTICE_TITLE_PT, NOTICE_TEXT_ES, NOTICE_TEXT_PT, LEGAL_CITES_ES, LEGAL_CITES_PT, APPEAL_FORM, RNR_NOTICE, LOGO_IND)
SELECT 
CO_MASS_MAILING_REQ_1SQ.NEXTVAL AS MASS_MAILING_SEQ_NUM,
0 AS MASS_MAILING_ID,
'IMPORTANT CHANGE TO MEDICAID ELIGIBILITY' AS NOTICE_TITLE,
TO_CLOB(' 
 ') || CHR(10) || '
You could lose Medicaid
 ' || CHR(10) || '
A new federal law changes who gets Medicaid. Starting on October 1, 2026, some people who are not U.S. citizens will lose Medicaid.
 ' || CHR(10) || '
This will not affect your Supplemental Security Income (SSI) benefits.
 ' || CHR(10) || '
Some people can keep Medicaid
 ' || CHR(10) || '
You can keep Medicaid if:
 ' || CHR(13) || ' ' || CHR(13) || ' • You are 0-18 years old (children).
 ' || CHR(13) || ' ' || CHR(13) || ' • You are pregnant or had a baby in the last year.
 ' || CHR(13) || ' ' || CHR(13) || ' • You are a Green Card holder for 5 years or more or meet the exemption to the 5 years.
 ' || CHR(13) || ' ' || CHR(13) || ' • You are a Cuban/Haitian Entrant.
 ' || CHR(13) || ' ' || CHR(13) || ' • You are a COFA migrant from the Marshall Islands, Micronesia, or Palau.
 ' || CHR(10) || '
We need information from you
 ' || CHR(10) || '
 • If you are a U.S. citizen, please send us ONE of these documents:
 ' || CHR(13) || '    o A copy of your U.S. birth certificate
 ' || CHR(13) || '    o A copy of your certificate of U.S. Citizenship (N-560 or N-561)
 ' || CHR(13) || '    o A copy of your final adoption decree showing you were born in the U.S.
 ' || CHR(13) || '    o A copy of your Military Record showing you were born in the U.S.
 ' || CHR(13) || '    o A copy of your Certificate of Naturalization
 ' || CHR(13) || '    o A copy of your Certificate of birth abroad of U.S. citizen (DS-1350, FS-240, FS-545).
 ' || CHR(13) || '    o A copy of your U.S. Passport
 ' || CHR(13) || ' • If you are a Green Card holder (permanent resident), please send us:
 ' || CHR(13) || '    o A copy of your Green Card.
 ' || CHR(13) || ' • If you are a Cuban/Haitian Entrant, please send us:
 ' || CHR(13) || '    o A copy of your Form I-94, Arrival/Departure Record with a stamp showing "Cuban Haitian Entrant" (Status Pending) or parole under 212(d)(5)
 ' || CHR(13) || '    o Other proof showing you are a Cuban Haitian Entrant. Please see the enclosed ADR for details.
 ' || CHR(13) || ' • If you are a COFA migrant from the Marshall Islands, Micronesia, or Palau, please send ONE of the following:
 ' || CHR(13) || '    o A copy of your passport
 ' || CHR(13) || '    o A copy of your birth certificate
 ' || CHR(13) || '    o Other proof of citizenship
 ' || CHR(13) || ' • Send us this information by ' || TO_CHAR(TRUNC(SYSDATE) + 15, 'DD-MON-YYYY') || CHR(10) || '
 ' || CHR(10) || '
If you do not send this information, you will lose Medicaid.
 ' || CHR(10) || '
How do I submit my documents?
 ' || CHR(10) || '
Important: Do NOT send your real papers. Send copies. We cannot send papers back to you.
 ' || CHR(13) || '1. Make a copy of your documents.
 ' || CHR(13) || '2. Put all information in an envelope.
 ' || CHR(13) || '3. Mail the letter or drop it off to:
 ' || CHR(13) || '   EOHHS
 ' || CHR(13) || '   Attn: SSI unit
 ' || CHR(13) || '   3 West Road
 ' || CHR(13) || '   CRANSTON, RI 02920-3028
 ' || CHR(10) || '
If you lose Medicaid there are other ways to get health insurance.
 ' || CHR(10) || '
You can buy health insurance for you and your family. You can buy insurance:
 ' || CHR(13) || ' • Online: Go to HealthSourceRI.com
 ' || CHR(13) || ' • By Phone: Call 1-855-840-4774
 ' || CHR(13) || ' • At Work: Ask your boss if your job offers health insurance.
 ' || CHR(13) || '    o Some jobs offer insurance to family members.
 ' || CHR(13) || '    o If you are under 26, see if your parents'' job offers insurance.
 ' || CHR(13) || ' • There are only certain times you can buy insurance, including
 ' || CHR(13) || '    o After you lose Medicaid.
 ' || CHR(13) || '    o During "Open Enrollment" in November and early December.
 ' || CHR(13) || '    o If you start a new job.
 ' || CHR(13) || '    o If you get married, divorced, or have a child.
 ' || CHR(13) || '    o If you have another special life event.
 ' || CHR(13) || ' • You can also buy an insurance plan from Neighborhood Health Plan of Rhode Island or Blue Cross & Blue Shield of Rhode Island.
 ' || CHR(10) || '
You can still get health care
 ' || CHR(10) || '
If you do not have insurance and are not a U.S. citizen, you can get care at:
 ' || CHR(13) || ' • Community Health Centers: rihca.org
 ' || CHR(13) || ' • Certified Community Behavioral Health Clinics: bhddh.ri.gov/CCBHC
 ' || CHR(13) || ' • Rhode Island Free Clinic: rifreeclinic.org
 ' || CHR(13) || ' • Clinica Esperanza: aplacetobehealthy.org
 ' || CHR(13) || ' • Emergency rooms: You can go to a hospital for an emergency, but you may have to pay. Local hospitals are required by law to give emergency medical care for serious or life-threatening problems, no matter your insurance or immigration status.
 ' || CHR(10) || '
What should I do now?
 ' || CHR(13) || ' - Send us your information if you are a U.S. citizen, Green Card holder (permanent resident), Cuban/Haitian entrant, or a COFA migrant.
 ' || CHR(13) || ' - Go to the doctor and get your prescriptions filled while you still have Medicaid.
 ' || CHR(13) || ' - See if you can get other health insurance before October 1.
 ' || CHR(13) || ' - You will get a letter in September letting you know if you lose Medicaid.
 ' || CHR(10) || '
Questions?
 ' || CHR(10) || '
Call 211 or visit staycovered.ri.gov/updates.
 ' || CHR(10) || '
'
AS NOTICE_TXT,
'' AS LEGAL_CITES,
NULL AS STD_TEXT_LST,
'CSV File' AS PROGRAM_LST,
TRUNC(SYSDATE) AS SCHD_DT,
I.CASE_NUM AS AUTHOR,
'N' AS JOB_PROCESSED_SW,
'RIB-183899' AS CREATE_USER_ID,
SYSDATE AS CREATE_DT,
CO_MASS_MAILING_REQ_0SQ.NEXTVAL AS UNIQUE_TRANS_ID,
TO_DATE('31-DEC-2999','DD-MON-RRRR') AS ARCHIVE_DT,
CO_MASS_MAILING_REQ_2SQ.NEXTVAL AS HISTORY_SEQ,
I.CASE_NUM AS CASE_NUM_LIST,
'Cambio importante en la elegibilidad de Medicaid' AS NOTICE_TITLE_ES,
'Mudança Importante na Elegibilidade do Medicaid' AS NOTICE_TITLE_PT,
TO_CLOB(' 
 ') || CHR(10) || '
Podría perder su cobertura de Medicaid
 ' || CHR(10) || '
Una nueva ley federal cambiará quién puede recibir Medicaid. A partir del 1 de octubre de 2026, algunas personas que no son ciudadanas estadounidenses perderán su cobertura de Medicaid.
 ' || CHR(10) || '
Esto no afectará sus beneficios de Seguridad de Ingreso Suplementario (SSI).
 ' || CHR(10) || '
Algunas personas pueden conservar su cobertura de Medicaid
 ' || CHR(10) || '
Puede conservar su cobertura de Medicaid en los siguientes casos:
 ' || CHR(13) || ' ' || CHR(13) || ' • Tiene entre 0 y 18 años (niños).
 ' || CHR(13) || ' ' || CHR(13) || ' • Está embarazada o tuvo un bebé en el último año.
 ' || CHR(13) || ' ' || CHR(13) || ' • Es titular de una tarjeta verde desde hace 5 años o más, o cumple con la exención de los 5 años.
 ' || CHR(13) || ' ' || CHR(13) || ' • Es una persona cubana/haitiana con categoría de entrada.
 ' || CHR(13) || ' ' || CHR(13) || ' • Es un migrante conforme al Compacto de Libre Asociación (COFA) de las Islas Marshall, Micronesia o Palaos.
 ' || CHR(10) || '
Necesitamos que nos facilite información
 ' || CHR(10) || '
 • Si es ciudadano estadounidense, envíenos UNO de estos documentos:
 ' || CHR(13) || '    o Una copia de su certificado de nacimiento estadounidense.
 ' || CHR(13) || '    o Una copia de su certificado de ciudadanía estadounidense (N-560 o N-561).
 ' || CHR(13) || '    o Una copia de su sentencia definitiva de adopción que muestre que nació en los Estados Unidos.
 ' || CHR(13) || '    o Una copia de su expediente militar que muestre que nació en los Estados Unidos.
 ' || CHR(13) || '    o Una copia de su certificado de naturalización.
 ' || CHR(13) || '    o Una copia de su certificado de nacimiento en el extranjero como ciudadano estadounidense (DS-1350, FS-240, FS-545).
 ' || CHR(13) || '    o Una copia de su pasaporte estadounidense.
 ' || CHR(13) || ' • Si es titular de una tarjeta verde (residente permanente), envíenos lo siguiente:
 ' || CHR(13) || '    o Una copia de su tarjeta verde.
 ' || CHR(13) || ' • Si es cubano/haitiano con categoría de entrada, envíenos lo siguiente:
 ' || CHR(13) || '    o Una copia de su Formulario I-94, Registro de entrada y salida, con un sello que indique "cubano-haitiano con categoría de entrada" (estatus pendiente) o un permiso de ingreso en virtud del artículo 212(d)(5).
 ' || CHR(13) || '    o Otra prueba que muestre que es una persona cubana/haitiana con categoría de entrada. Consulte la solicitud de documentación adicional (ADR) adjunta para obtener más información.
 ' || CHR(13) || ' • Si es un migrante conforme al COFA de las Islas Marshall, Micronesia o Palaos, envíe UNO de los siguientes documentos:
 ' || CHR(13) || '    o Una copia de su pasaporte.
 ' || CHR(13) || '    o Una copia de su certificado de nacimiento.
 ' || CHR(13) || '    o Otra prueba de ciudadanía.
 ' || CHR(13) || ' • Envíenos esta información antes del ' || TO_CHAR(TRUNC(SYSDATE) + 15, 'DD-MON-YYYY') || CHR(10) || '.
 ' || CHR(10) || '
Si no nos envía esta información, perderá su cobertura de Medicaid.
 ' || CHR(10) || '
¿Cómo envío mis documentos?
 ' || CHR(10) || '
Importante: NO envíe sus documentos impresos originales. Envíe copias. No podemos devolverle los documentos.
 ' || CHR(13) || '1. Haga una copia de sus documentos.
 ' || CHR(13) || '2. Coloque toda la información en un sobre.
 ' || CHR(13) || '3. Envíe la carta o déjela en:
 ' || CHR(13) || '   EOHHS
 ' || CHR(13) || '   Attn: SSI unit
 ' || CHR(13) || '   3 West Road
 ' || CHR(13) || '   CRANSTON, RI 02920-3028
 ' || CHR(10) || '
Si pierde su cobertura de Medicaid, existen otras maneras de obtener un seguro médico.
 ' || CHR(10) || '
Puede comprar un seguro médico para usted y su familia. Puede hacerlo de las siguientes maneras:
 ' || CHR(13) || ' • En línea: ingrese en HealthSourceRI.com
 ' || CHR(13) || ' • Por teléfono: llame al 1-855-840-4774
 ' || CHR(13) || ' • En el trabajo: consulte con su jefe si el trabajo ofrece un seguro médico.
 ' || CHR(13) || '    o Algunos trabajos ofrecen un seguro a miembros de la familia.
 ' || CHR(13) || '    o Si es menor de 26 años, consulte si el trabajo de sus padres ofrece un seguro.
 ' || CHR(13) || ' • Existen solo determinados momentos en los que puede comprar un seguro, entre los que se incluyen los siguientes:
 ' || CHR(13) || '    o Después de perder su cobertura de Medicaid.
 ' || CHR(13) || '    o Durante la "Inscripción abierta" en noviembre y a principios de diciembre.
 ' || CHR(13) || '    o Si comienza un nuevo trabajo.
 ' || CHR(13) || '    o Si contrae matrimonio, se divorcia o tiene un hijo.
 ' || CHR(13) || '    o Si tiene otro evento de vida especial.
 ' || CHR(13) || ' • También puede comprar un plan de seguro de Neighborhood Health Plan of Rhode Island o de Blue Cross & Blue Shield of Rhode Island.
 ' || CHR(10) || '
Puede seguir recibiendo atención médica
 ' || CHR(10) || '
Si no tiene un seguro y no es un ciudadano estadounidense, puede recibir atención en los siguientes lugares:
 ' || CHR(13) || ' • Centros de Salud Comunitaria: rihca.org
 ' || CHR(13) || ' • Clínicas Certificadas de Salud Comunitaria/Conductual: bhddh.ri.gov/CCBHC
 ' || CHR(13) || ' • Clínica Gratuita de Rhode Island: rifreeclinic.org
 ' || CHR(13) || ' • Clínica Esperanza: aplacetobehealthy.org
 ' || CHR(13) || ' • Salas de emergencia: puede acudir a un hospital para tratar una emergencia, pero es probable que tenga que pagar. Los hospitales locales están obligados por ley a prestar atención médica de emergencia para problemas graves o que representen un riesgo para la vida, sin importar su seguro o situación migratoria.
 ' || CHR(10) || '
¿Qué debo hacer ahora?
 ' || CHR(13) || ' - Envíenos su información si es un ciudadano estadounidense, titular de una tarjeta verde (residente permanente), persona cubana/haitiana con categoría de entrada o migrante conforme al COFA.
 ' || CHR(13) || ' - Acuda al médico y surta sus recetas mientras todavía tenga Medicaid.
 ' || CHR(13) || ' - Verifique si puede obtener otro seguro médico antes del 1 de octubre.
 ' || CHR(13) || ' - Recibirá una carta en septiembre que le indicará si conserva o pierde su cobertura de Medicaid.
 ' || CHR(10) || '
¿Tiene preguntas?
 ' || CHR(10) || '
Llame al 211 o visite staycovered.ri.gov/updates.
 ' || CHR(10) || '
'
AS NOTICE_TEXT_ES,
TO_CLOB(' 
 ') || CHR(10) || '
Pode perder o Medicaid
 ' || CHR(10) || '
Uma nova lei federal altera os critérios de elegibilidade para o Medicaid. A partir de 1 de outubro de 2026, algumas pessoas que não sejam cidadãos dos EUA perderão o Medicaid.
 ' || CHR(10) || '
Isto não afetará os seus benefícios do Programa de Rendimento Suplementar de Segurança (Supplemental Security Income, SSI).
 ' || CHR(10) || '
Algumas pessoas podem manter o Medicaid
 ' || CHR(10) || '
Pode manter o Medicaid se:
 ' || CHR(13) || ' ' || CHR(13) || ' • Tiver entre 0 e 18 anos (crianças).
 ' || CHR(13) || ' ' || CHR(13) || ' • Estiver grávida ou tiver tido um filho no último ano.
 ' || CHR(13) || ' ' || CHR(13) || ' • For titular de um Green Card (Cartão de Residente Permanente) há 5 anos ou mais, ou se preencher os requisitos para a isenção do requisito dos 5 anos.
 ' || CHR(13) || ' ' || CHR(13) || ' • For um imigrante cubano ou haitiano.
 ' || CHR(13) || ' ' || CHR(13) || ' • For um migrante abrangido pelo COFA proveniente das Ilhas Marshall, da Micronésia ou de Palau.
 ' || CHR(10) || '
Precisamos que nos forneça informações!
 ' || CHR(10) || '
 • Se for cidadão dos EUA, envie-nos UM destes documentos:
 ' || CHR(13) || '    o Uma cópia da sua Certidão de Nascimento dos EUA
 ' || CHR(13) || '    o Uma cópia do seu Certificado de Cidadania dos EUA (N-560 ou N-561)
 ' || CHR(13) || '    o Uma cópia da sua decisão judicial definitiva de adoção que comprove que nasceu nos EUA.
 ' || CHR(13) || '    o Uma cópia do seu Registo Militar que comprove que nasceu nos EUA.
 ' || CHR(13) || '    o Uma cópia do seu Certificado de Naturalização
 ' || CHR(13) || '    o Uma cópia da sua Certidão de Nascimento no estrangeiro de cidadão dos EUA (DS-1350, FS-240, FS-545).
 ' || CHR(13) || '    o Uma cópia do seu Passaporte dos EUA
 ' || CHR(13) || ' • Se for titular de um Green Card (Cartão de Residente Permanente), envie-nos:
 ' || CHR(13) || '    o Uma cópia do seu Green Card.
 ' || CHR(13) || ' • Se for um imigrante cubano ou haitiano, envie-nos:
 ' || CHR(13) || '    o Uma cópia do seu Formulário I-94, Registo de Chegada/Partida, com um carimbo que indique "Imigrante cubano-haitiano" (Estatuto pendente) ou autorização provisória ao abrigo do artigo 212(d)(5)
 ' || CHR(13) || '    o Outros documentos comprovativos de que é um imigrante cubano-haitiano. Para mais informações, consulte o ADR em anexo.
 ' || CHR(13) || ' • Se for um migrante COFA proveniente das Ilhas Marshall, da Micronésia ou de Palau, envie UMA das seguintes opções:
 ' || CHR(13) || '    o Uma cópia do seu passaporte
 ' || CHR(13) || '    o Uma cópia da sua certidão de nascimento
 ' || CHR(13) || '    o Outros documentos comprovativos de cidadania
 ' || CHR(13) || ' • Envie-nos esta informação até ' || TO_CHAR(TRUNC(SYSDATE) + 15, 'DD-MON-YYYY') || CHR(10) || '
 ' || CHR(10) || '
Se não enviar estas informações, perderá o direito ao Medicaid.
 ' || CHR(10) || '
Como é que envio os meus documentos?
 ' || CHR(10) || '
Importante: NÃO envie os seus documentos originais. Envie cópias. Não podemos devolver-lhe os documentos.
 ' || CHR(13) || '1. Faça uma cópia dos seus documentos.
 ' || CHR(13) || '2. Coloque toda a informação num envelope.
 ' || CHR(13) || '3. Envie a carta por correio ou entregue-a pessoalmente em:
 ' || CHR(13) || '   EOHHS
 ' || CHR(13) || '   Attn: SSI unit
 ' || CHR(13) || '   3 West Road
 ' || CHR(13) || '   CRANSTON, RI 02920-3028
 ' || CHR(10) || '
Se perder o Medicaid, existem outras formas de obter um seguro de saúde.
 ' || CHR(10) || '
Pode subscrever um seguro de saúde para si e para a sua família. Para subscrever um seguro:
 ' || CHR(13) || ' • Online: Aceda a HealthSourceRI.com
 ' || CHR(13) || ' • Telefone: Ligue para o número 1-855-840-4774
 ' || CHR(13) || ' • No trabalho: Pergunte ao seu chefe se o seu emprego oferece seguro de saúde.
 ' || CHR(13) || '    o Alguns empregos oferecem seguro aos familiares.
 ' || CHR(13) || '    o Se tiver menos de 26 anos, verifique se o emprego dos seus pais oferece seguro.
 ' || CHR(13) || ' • Só é possível subscrever um seguro em determinadas alturas, incluindo:
 ' || CHR(13) || '    o Depois de deixar de ter direito ao Medicaid.
 ' || CHR(13) || '    o Durante o "Período de Inscrição Aberta", em novembro e no início de dezembro.
 ' || CHR(13) || '    o Quando inicia um novo emprego.
 ' || CHR(13) || '    o Quando se casa, divorcia ou tem um filho.
 ' || CHR(13) || '    o Caso ocorra outro acontecimento especial na sua vida.
 ' || CHR(13) || ' • Também pode subscrever um plano de seguro junto do Neighborhood Health Plan of Rhode Island ou da Blue Cross & Blue Shield of Rhode Island.
 ' || CHR(10) || '
Ainda pode ter acesso a cuidados de saúde
 ' || CHR(10) || '
Se não tiver seguro e não for cidadão dos EUA, pode receber cuidados de saúde nos seguintes locais:
 ' || CHR(13) || ' • Centros de Saúde Comunitários: rihca.org
 ' || CHR(13) || ' • Clínicas Comunitárias de Saúde Comportamental Certificadas: bhddh.ri.gov/CCBHC
 ' || CHR(13) || ' • Rhode Island Free Clinic: rifreeclinic.org
 ' || CHR(13) || ' • Clinica Esperanza: aplacetobehealthy.org
 ' || CHR(13) || ' • Serviços de urgência: Pode dirigir-se a um hospital em caso de emergência, mas poderá ter de pagar. Os hospitais locais são obrigados por lei a prestar cuidados médicos de emergência em caso de problemas graves ou que ponham a vida em risco, independentemente do seu seguro ou estatuto de imigração.
 ' || CHR(10) || '
O que devo fazer agora?
 ' || CHR(13) || ' - Envie-nos os seus dados se for cidadão dos EUA, titular de Green Card (Cartão de Residente Permanente), imigrante cubano/haitiano ou migrante ao abrigo do COFA.
 ' || CHR(13) || ' - Vá ao médico e avie as suas receitas enquanto ainda tem o Medicaid.
 ' || CHR(13) || ' - Veja se consegue obter outro seguro de saúde antes de 1 de outubro.
 ' || CHR(13) || ' - Vai receber uma carta em setembro. Isso dir-lhe-á se vai manter ou perder o Medicaid.
 ' || CHR(10) || '
Alguma dúvida?
 ' || CHR(10) || '
Ligue para o 211 ou visite staycovered.ri.gov/updates.
 ' || CHR(10) || '
'
AS NOTICE_TEXT_PT,
'' AS LEGAL_CITES_ES,
'' AS LEGAL_CITES_PT,
'' AS APPEAL_FORM,
'' AS RNR_NOTICE,
'' AS LOGO_IND
FROM DUAL;

TOT_CT :=TOT_CT + SQL%ROWCOUNT;

 INSERT /*+parallel(4)*/
               INTO IE_APP_ONLINE.DC_CASE_NOTES (CASE_NUM,
                                   CASE_NOTES_SEQ_NUM,
                                   DESCRIPTION_CD,
                                   ADDL_INFO,
                                   HMK_MARKED_FOR_REVIEW_SW,
                                   HIPPA_PROTECTED_SW,
                                   HISTORY_SEQ,
                                   CREATE_USER_ID,
                                   CREATE_DT,
                                   UNIQUE_TRANS_ID,
                                   ARCHIVE_DT,
                                   BENEFIT_MONTH_DT,
                                   NOTES_TXT,
                                   PAGE_ID)
            SELECT I.CASE_NUM,
                   DC_CASE_NOTES_1SQ.NEXTVAL,
                   'OTHE',
                   NULL,
                   'N',
                   'N',
                   DC_CASE_NOTES_2SQ.NEXTVAL,
                   'RIB-183899', -----UPDATE
                   TRUNC(SYSDATE),
                   DC_CASE_NOTES_0SQ.NEXTVAL,
                   TO_DATE ('31-DEC-2999', 'DD-MON-YYYY'),
                   NULL,
				   'Customer(s) on this case were sent a manual notice to update DHS of any immigration status changes prior to implementation of non-citizen rules related to HR1. More information is available with SR RIB-182739.',
                   'DCELE'
              FROM DUAL D
			  WHERE NOT EXISTS (SELECT 1 FROM IE_APP_ONLINE.DC_CASE_NOTES D WHERE D.CASE_NUM = I.CASE_NUM AND D.CREATE_USER_ID = 'RIB-183899')
			  AND EXISTS(SELECT 1 FROM IE_APP_ONLINE.DC_CASES DC WHERE DC.CASE_NUM = I.CASE_NUM);

TOT_CN_CT  :=TOT_CN_CT + SQL%ROWCOUNT;

END LOOP;
DBMS_OUTPUT.PUT_LINE ('Total Manual Notice Inserted For Cases : ' ||TOT_CT);
DBMS_OUTPUT.PUT_LINE ('Total case notes Inserted For Cases : ' ||TOT_CN_CT);
END;
/

UPDATE BKUP_TABLES.MN_IMP_POPULATION_183899 B
SET
B.NOTICE_TRIGGERED = 'Y',
B.NOTICE_TRIGGERED_DT = SYSDATE
WHERE 
NVL(B.NOTICE_TRIGGERED,'N') = 'N'
AND B.NOTICE_TRIGGERED_DT IS NULL
AND B.CASE_NUM IN (SELECT DISTINCT TO_NUMBER(C.CASE_NUM_LIST) CASE_NUM FROM IE_APP_ONLINE.CO_MASS_MAILING_REQ C WHERE C.CREATE_USER_ID = 'RIB-183899' AND C.CREATE_DT >= TRUNC(SYSDATE-1))
;
COMMIT; 

UPDATE BKUP_TABLES.TRIGGER_INFO_183899 B
SET
B.NOTICE_TRIGGERED = 'Y',
B.NOTICE_TRIGGERED_DT = SYSDATE
WHERE 
NVL(B.NOTICE_TRIGGERED,'N') = 'N'
AND B.NOTICE_TRIGGERED_DT IS NULL
AND B.CASE_NUM IN (SELECT DISTINCT TO_NUMBER(C.CASE_NUM_LIST) CASE_NUM FROM IE_APP_ONLINE.CO_MASS_MAILING_REQ C WHERE C.CREATE_USER_ID = 'RIB-183899' AND C.CREATE_DT >= TRUNC(SYSDATE-1))
;
COMMIT; 
