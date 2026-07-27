/*
***************************************************************************************************************************************************
JIRA NUMBER: RIB-183903
JIRA DESCRIPTION: RIB-182739 : Section 71109 - SSI population - Text to Impacted Population
DEVELOPER : rjohri
PURPOSE: Insert SMS  Triggers for Impacted Cases
IMPACTED POPULATION: 
IMPACTED TABLES: 
a. HIX: NA
b. IES: CO_MAN_SMS_EMAIL_REQ
REVISION HISTORY:
***************************************************************************************************************************************************
*/

ALTER SESSION SET CURRENT_SCHEMA=IE_APP_ONLINE;

SET TIMING ON;

SET SERVEROUTPUT ON;

DECLARE
    cnt NUMBER;
BEGIN
    SELECT
        COUNT(1)
    INTO cnt
    FROM
        all_tables
    WHERE
            table_name = 'SMS_IMP_POPULATION_BASE_183903'
        AND owner = 'BKUP_TABLES';

    IF cnt = 0 THEN
        EXECUTE IMMEDIATE 'CREATE TABLE BKUP_TABLES.SMS_IMP_POPULATION_BASE_183903(CASE_NUM NUMBER, INDV_ID NUMBER, TOA VARCHAR2(30), RECORD_INS DATE) ';
    END IF;
END;
/

DECLARE
V_COUNT NUMBER:=0;
BEGIN
SELECT COUNT(*) INTO V_COUNT FROM ALL_TABLES WHERE OWNER = 'BKUP_TABLES' AND TABLE_NAME = 'CASES_RIB183903_SMS';
IF V_COUNT=0 THEN
EXECUTE IMMEDIATE 'CREATE TABLE BKUP_TABLES.CASES_RIB183903_SMS AS SELECT CASE_NUM AS CASE_NUMBER, 1234567899 AS PHONE_NUMBER, ASSIST_COMMENTS AS PHONE_NUMBER_TYPE,
''N'' AS OPT_IN, ''N'' AS AUTH_REP_AVAILABLE, SYSDATE AS RECORD_IDENTIFIED_ON, ''N'' AS SMS_TRIGGERED, SYSDATE AS TRIGGERED_ON, ''NA'' AS TRIGGER_STATUS, ASSIST_COMMENTS AS REC_COMMENT FROM DC_CASES WHERE 1<>1';
END IF;
END;
/

DECLARE
    CNT NUMBER;
BEGIN
    SELECT COUNT(1) INTO CNT FROM ALL_TABLES WHERE TABLE_NAME='IMPACTED_CASES_RIB183903_SMS' AND OWNER='BKUP_TABLES';
    IF CNT>0
    THEN EXECUTE IMMEDIATE 'DROP TABLE BKUP_TABLES.IMPACTED_CASES_RIB183903_SMS';
    END IF;
END;
/

INSERT INTO BKUP_TABLES.SMS_IMP_POPULATION_BASE_183903
(
    CASE_NUM,
    INDV_ID,
    TOA,
    RECORD_INS
)
WITH params AS
(
    SELECT DATE '2026-10-01' AS as_of_dt
    FROM dual
),
PREG_INDV AS
(
    SELECT /*+ PARALLEL(4) */
        INDV_ID
    FROM IE_APP_ONLINE.DC_PREGNANCIES
    CROSS JOIN params p
    WHERE p.as_of_dt > EFF_BEGIN_DT
      AND
      (
          EFF_END_DT IS NULL
          OR EFF_END_DT > p.as_of_dt
      )
      AND
      (
          (
              TERMINATION_DT IS NOT NULL
              AND TERMINATION_DT >= p.as_of_dt
          )
          OR
          (
              DUE_DT IS NOT NULL
              AND DUE_DT >= p.as_of_dt
          )
      )
),
POSTPARTUM_INDIV AS
(
    SELECT /*+ PARALLEL(4) */
        INDV_ID
    FROM IE_APP_ONLINE.DC_PREGNANCIES
    CROSS JOIN params p
    WHERE (TERMINATION_DT IS NOT NULL OR DUE_DT IS NOT NULL)
      AND NVL(TERMINATION_DT, DUE_DT) <= p.as_of_dt
      AND NVL(TERMINATION_DT, DUE_DT) >= ADD_MONTHS(p.as_of_dt, -12)
),
excluded_indv AS
(
    SELECT DISTINCT INDV_ID
    FROM PREG_INDV

    UNION

    SELECT DISTINCT INDV_ID
    FROM POSTPARTUM_INDIV
),
base_rows AS
(
    SELECT /*+ PARALLEL(16) */
        b.INDV_ID,
        a.CASE_NUM,
        a.EDG_TRACE_ID,
        a.TYPE_OF_ASSISTANCE_CD,
        a.EDBC_RUN_DT,
        c.SSN,
        dp.US_CITIZEN_SW,
        TRUNC(MONTHS_BETWEEN(p.as_of_dt, c.DOB_DT) / 12) AS AGE_IN_YEARS,
        d.READ_LANG_CD
    FROM IE_APP_ONLINE.DC_CASES d
    JOIN IE_APP_ONLINE.ED_ELIGIBILITY a
      ON a.CASE_NUM = d.CASE_NUM
    JOIN IE_APP_ONLINE.ED_INDV_ELIGIBILITY b
      ON a.CASE_NUM = b.CASE_NUM
     AND a.EDG_TRACE_ID = b.EDG_TRACE_ID
    JOIN IE_APP_ONLINE.DC_INDV c
      ON b.INDV_ID = c.INDV_ID
    LEFT JOIN IE_APP_ONLINE.DC_DEMOGRAPHICS dp
      ON c.INDV_ID = dp.INDV_ID
     AND dp.EFF_END_DT IS NULL
    CROSS JOIN params p
    WHERE a.TYPE_OF_ASSISTANCE_CD = 'TP13'
      AND b.TARGET_SW = 'Y'
      AND a.PAYMENT_END_DT IS NULL
      AND a.CG_STATUS_CD = 'AP'
      AND a.CURRENT_ELIG_IND = 'A'

      -- >>> CHANGED/ADDED: Preserve original SMS preference eligibility logic
      AND
      (
          d.SMS_PREF_SW = 'Y'
          OR d.SMS_PREF_SW IS NULL
          OR d.SMS_PREF_SW = ''
          OR d.SMS_PREF_SW = ' '
      )

      -- >>> CHANGED/ADDED: Preserve original verified case-phone requirement
      AND EXISTS
      (
          SELECT 1
          FROM IE_APP_ONLINE.DC_PHN_XREF XT
          JOIN IE_APP_ONLINE.DC_PHN_DETAILS DT
            ON DT.PHN_SEQ_NUM = XT.PHN_SEQ_NUM
          WHERE XT.PHN_SRC_ID = d.CASE_NUM
            AND XT.PHN_SRC_TYPE_CD = 'CS'
            AND DT.VERIFIED_SW = 'Y'
            AND DT.PHN_TYPE_CD = 'C'
      )

      AND NOT EXISTS
      (
          SELECT 1
          FROM excluded_indv x
          WHERE x.INDV_ID = b.INDV_ID
      )
),
latest_sdx AS
(
    SELECT y.SSN,
           y.ALIEN_IND_CD
    FROM
    (
        SELECT
            d.SSN,
            d.ALIEN_IND_CD,
            ROW_NUMBER() OVER
            (
                PARTITION BY d.SSN
                ORDER BY d.SDX_SEQ_NUM DESC
            ) AS RN
        FROM IE_APP_ONLINE.IN_SDX d
        JOIN
        (
            SELECT DISTINCT SSN
            FROM base_rows
        ) s
          ON s.SSN = d.SSN
    ) y
    WHERE y.RN = 1
      AND
      (
          y.ALIEN_IND_CD NOT IN
          (
              'A','B','C','R','Q','K','N','S','X','E','P'
          )
          OR y.ALIEN_IND_CD IS NULL
      )
),
sm AS
(
    SELECT
        i.INDV_ID,
        MAX
        (
            CASE
                WHEN e.TYPE_OF_ASSISTANCE_CD = 'SSPC'
                THEN 'Y'
            END
        ) AS SSPC_ELIGIBLE,
        MAX
        (
            CASE
                WHEN e.PROGRAM_CD = 'MC'
                THEN 'Y'
            END
        ) AS MC_ELIGIBLE
    FROM IE_APP_ONLINE.ED_ELIGIBILITY e
    JOIN IE_APP_ONLINE.ED_INDV_ELIGIBILITY i
      ON e.CASE_NUM = i.CASE_NUM
     AND e.EDG_TRACE_ID = i.EDG_TRACE_ID
    JOIN
    (
        SELECT DISTINCT INDV_ID, CASE_NUM
        FROM base_rows
    ) b
      ON b.INDV_ID = i.INDV_ID
     AND b.CASE_NUM = i.CASE_NUM
    WHERE e.CURRENT_ELIG_IND = 'A'
      AND e.CG_STATUS_CD IN ('AP', 'CE')
      AND i.TARGET_SW = 'Y'
      AND e.PAYMENT_END_DT IS NULL
      AND
      (
          e.TYPE_OF_ASSISTANCE_CD = 'SSPC'
          OR e.PROGRAM_CD = 'MC'
      )
      AND e.DELETE_SW = 'N'
    GROUP BY i.INDV_ID
),
IMPACTED_POPULATION AS
(
    SELECT DISTINCT
        b.INDV_ID,
        b.CASE_NUM,
        b.EDBC_RUN_DT,
        b.TYPE_OF_ASSISTANCE_CD AS TOA,
        d.ALIEN_IND_CD,
        NVL(sm.SSPC_ELIGIBLE, 'N') AS SSPC_ELIGIBLE,
        NVL(sm.MC_ELIGIBLE, 'N') AS MC_ELIGIBLE,
        rt.DESCRIPTION
    FROM base_rows b
    JOIN latest_sdx d
      ON d.SSN = b.SSN
    LEFT JOIN sm
      ON sm.INDV_ID = b.INDV_ID
    LEFT JOIN IE_APP_ONLINE.RT_LANGUAGE_MV rt
      ON rt.CODE = b.READ_LANG_CD
    WHERE
    (
        d.ALIEN_IND_CD NOT IN
        (
            'A','B','C','R','Q','K','N','S','X','E','P'
        )
        OR
        (
            d.ALIEN_IND_CD IS NULL
            AND b.US_CITIZEN_SW = 'N'
        )
    )
    AND b.AGE_IN_YEARS > 19
)
SELECT
    A.CASE_NUM,
    A.INDV_ID,
    A.TOA,
    SYSDATE AS RECORD_INS
FROM IMPACTED_POPULATION A
WHERE NOT EXISTS
(
    SELECT 1
    FROM BKUP_TABLES.SMS_IMP_POPULATION_BASE_183903 B
    WHERE A.CASE_NUM = B.CASE_NUM
      AND A.INDV_ID = B.INDV_ID
);
	

INSERT INTO BKUP_TABLES.CASES_RIB183903_SMS (CASE_NUMBER, PHONE_NUMBER, PHONE_NUMBER_TYPE, OPT_IN, AUTH_REP_AVAILABLE,RECORD_IDENTIFIED_ON)
WITH
WITH params AS
(
    SELECT DATE '2026-10-01' AS as_of_dt
    FROM dual
),
PREG_INDV AS
(
    SELECT /*+ PARALLEL(4) */
        INDV_ID
    FROM IE_APP_ONLINE.DC_PREGNANCIES
    CROSS JOIN params p
    WHERE p.as_of_dt > EFF_BEGIN_DT
      AND
      (
          EFF_END_DT IS NULL
          OR EFF_END_DT > p.as_of_dt
      )
      AND
      (
          (
              TERMINATION_DT IS NOT NULL
              AND TERMINATION_DT >= p.as_of_dt
          )
          OR
          (
              DUE_DT IS NOT NULL
              AND DUE_DT >= p.as_of_dt
          )
      )
),
POSTPARTUM_INDIV AS
(
    SELECT /*+ PARALLEL(4) */
        INDV_ID
    FROM IE_APP_ONLINE.DC_PREGNANCIES
    CROSS JOIN params p
    WHERE (TERMINATION_DT IS NOT NULL OR DUE_DT IS NOT NULL)
      AND NVL(TERMINATION_DT, DUE_DT) <= p.as_of_dt
      AND NVL(TERMINATION_DT, DUE_DT) >= ADD_MONTHS(p.as_of_dt, -12)
),
excluded_indv AS
(
    SELECT DISTINCT INDV_ID
    FROM PREG_INDV

    UNION

    SELECT DISTINCT INDV_ID
    FROM POSTPARTUM_INDIV
),
base_rows AS
(
    SELECT /*+ PARALLEL(16) */
        b.INDV_ID,
        a.CASE_NUM,
        a.EDG_TRACE_ID,
        a.TYPE_OF_ASSISTANCE_CD,
        a.EDBC_RUN_DT,
        c.SSN,
        dp.US_CITIZEN_SW,
        TRUNC(MONTHS_BETWEEN(p.as_of_dt, c.DOB_DT) / 12) AS AGE_IN_YEARS,
        d.READ_LANG_CD
    FROM IE_APP_ONLINE.DC_CASES d
    JOIN IE_APP_ONLINE.ED_ELIGIBILITY a
      ON a.CASE_NUM = d.CASE_NUM
    JOIN IE_APP_ONLINE.ED_INDV_ELIGIBILITY b
      ON a.CASE_NUM = b.CASE_NUM
     AND a.EDG_TRACE_ID = b.EDG_TRACE_ID
    JOIN IE_APP_ONLINE.DC_INDV c
      ON b.INDV_ID = c.INDV_ID
    LEFT JOIN IE_APP_ONLINE.DC_DEMOGRAPHICS dp
      ON c.INDV_ID = dp.INDV_ID
     AND dp.EFF_END_DT IS NULL
    CROSS JOIN params p
    WHERE a.TYPE_OF_ASSISTANCE_CD = 'TP13'
      AND b.TARGET_SW = 'Y'
      AND a.PAYMENT_END_DT IS NULL
      AND a.CG_STATUS_CD = 'AP'
      AND a.CURRENT_ELIG_IND = 'A'

      AND
      (
          d.SMS_PREF_SW = 'Y'
          OR d.SMS_PREF_SW IS NULL
          OR d.SMS_PREF_SW = ''
          OR d.SMS_PREF_SW = ' '
      )

      -- >>> CHANGED/ADDED: Preserve original verified case-phone requirement
      AND EXISTS
      (
          SELECT 1
          FROM IE_APP_ONLINE.DC_PHN_XREF XT
          JOIN IE_APP_ONLINE.DC_PHN_DETAILS DT
            ON DT.PHN_SEQ_NUM = XT.PHN_SEQ_NUM
          WHERE XT.PHN_SRC_ID = d.CASE_NUM
            AND XT.PHN_SRC_TYPE_CD = 'CS'
            AND DT.VERIFIED_SW = 'Y'
            AND DT.PHN_TYPE_CD = 'C'
      )

      AND NOT EXISTS
      (
          SELECT 1
          FROM excluded_indv x
          WHERE x.INDV_ID = b.INDV_ID
      )
),
latest_sdx AS
(
    SELECT y.SSN,
           y.ALIEN_IND_CD
    FROM
    (
        SELECT
            d.SSN,
            d.ALIEN_IND_CD,
            ROW_NUMBER() OVER
            (
                PARTITION BY d.SSN
                ORDER BY d.SDX_SEQ_NUM DESC
            ) AS RN
        FROM IE_APP_ONLINE.IN_SDX d
        JOIN
        (
            SELECT DISTINCT SSN
            FROM base_rows
        ) s
          ON s.SSN = d.SSN
    ) y
    WHERE y.RN = 1
      AND
      (
          y.ALIEN_IND_CD NOT IN
          (
              'A','B','C','R','Q','K','N','S','X','E','P'
          )
          OR y.ALIEN_IND_CD IS NULL
      )
),
sm AS
(
    SELECT
        i.INDV_ID,
        MAX
        (
            CASE
                WHEN e.TYPE_OF_ASSISTANCE_CD = 'SSPC'
                THEN 'Y'
            END
        ) AS SSPC_ELIGIBLE,
        MAX
        (
            CASE
                WHEN e.PROGRAM_CD = 'MC'
                THEN 'Y'
            END
        ) AS MC_ELIGIBLE
    FROM IE_APP_ONLINE.ED_ELIGIBILITY e
    JOIN IE_APP_ONLINE.ED_INDV_ELIGIBILITY i
      ON e.CASE_NUM = i.CASE_NUM
     AND e.EDG_TRACE_ID = i.EDG_TRACE_ID
    JOIN
    (
        SELECT DISTINCT INDV_ID, CASE_NUM
        FROM base_rows
    ) b
      ON b.INDV_ID = i.INDV_ID
     AND b.CASE_NUM = i.CASE_NUM
    WHERE e.CURRENT_ELIG_IND = 'A'
      AND e.CG_STATUS_CD IN ('AP', 'CE')
      AND i.TARGET_SW = 'Y'
      AND e.PAYMENT_END_DT IS NULL
      AND
      (
          e.TYPE_OF_ASSISTANCE_CD = 'SSPC'
          OR e.PROGRAM_CD = 'MC'
      )
      AND e.DELETE_SW = 'N'
    GROUP BY i.INDV_ID
),
FINAL_SET AS
(
    
    SELECT DISTINCT
        b.INDV_ID,
        b.CASE_NUM,
        b.EDBC_RUN_DT,
        b.TYPE_OF_ASSISTANCE_CD AS TOA,
        d.ALIEN_IND_CD,
        NVL(sm.SSPC_ELIGIBLE, 'N') AS SSPC_ELIGIBLE,
        NVL(sm.MC_ELIGIBLE, 'N') AS MC_ELIGIBLE,
        rt.DESCRIPTION
    FROM base_rows b
    JOIN latest_sdx d
      ON d.SSN = b.SSN
    LEFT JOIN sm
      ON sm.INDV_ID = b.INDV_ID
    LEFT JOIN IE_APP_ONLINE.RT_LANGUAGE_MV rt
      ON rt.CODE = b.READ_LANG_CD
    WHERE
    (
        d.ALIEN_IND_CD NOT IN
        (
            'A','B','C','R','Q','K','N','S','X','E','P'
        )
        OR
        (
            d.ALIEN_IND_CD IS NULL
            AND b.US_CITIZEN_SW = 'N'
        )
    )
    AND b.AGE_IN_YEARS > 19
  
),
PHONE_ONE AS
(
    SELECT
        XT.PHN_SRC_ID AS CASE_NUM,
        DT.PHN_NUM,
        DT.PHN_TYPE_CD
    FROM IE_APP_ONLINE.DC_PHN_XREF XT
    JOIN IE_APP_ONLINE.DC_PHN_DETAILS DT
      ON DT.PHN_SEQ_NUM = XT.PHN_SEQ_NUM
    WHERE XT.PHN_SRC_TYPE_CD = 'CS'
      AND DT.VERIFIED_SW = 'Y'
      AND DT.PHN_TYPE_CD = 'C'
),
AUTH_REP_FLAG AS
(
    SELECT
        DAR.CASE_NUM,
        DAR.PRIMARY_PHN_NUM,
        DAR.EMAIL,
        DAR.PRIMARY_PHN_TYPE_CD,
        DAR.CONTACT_METHOD_CD,
        'Y' AS AUTH_REP_AVAILABLE
    FROM IE_APP_ONLINE.DC_AUTH_REP DAR
    WHERE DAR.AUTH_REP_TYPE_CD = 'S'
      AND (DAR.END_DT IS NULL OR DAR.END_DT > SYSDATE)
    GROUP BY
        DAR.CASE_NUM,
        DAR.PRIMARY_PHN_NUM,
        DAR.EMAIL,
        DAR.PRIMARY_PHN_TYPE_CD,
        DAR.CONTACT_METHOD_CD
)
SELECT DISTINCT
    CASE_NUMBER,
    PHONE_NUMBER,
    PHONE_NUMBER_TYPE,
    OPT_IN,
    AUTH_REP_AVAILABLE,
    RECORD_IDENTIFIED_ON
FROM
(
    SELECT DISTINCT /*+ PARALLEL(8) LEADING(FS DC) */
        FS.CASE_NUM AS CASE_NUMBER,
        CASE
            WHEN AR.AUTH_REP_AVAILABLE = 'Y'
            THEN AR.PRIMARY_PHN_NUM
            WHEN NVL(AR.AUTH_REP_AVAILABLE, 'N') = 'N'
                 AND P1.PHN_NUM IS NOT NULL
            THEN P1.PHN_NUM
            ELSE 'NA'
        END AS PHONE_NUMBER,
        NVL(RTP.DESCRIPTION, 'NA') AS PHONE_NUMBER_TYPE,
        NVL(UPPER(TRIM(DC.SMS_PREF_SW)), 'N') AS OPT_IN,
        NVL(AR.AUTH_REP_AVAILABLE, 'N') AS AUTH_REP_AVAILABLE,
        (
            SELECT TO_DATE(PARAMETERS, 'MM/DD/YYYY')
            FROM IE_APP_MRS_OWNER.FW_BATCH_PARAMETER_CONTROL
            WHERE JOB_ID = 'FW-GLOBL-DLY'
        ) AS RECORD_IDENTIFIED_ON
    FROM FINAL_SET FS
    JOIN IE_APP_ONLINE.DC_CASES DC
      ON DC.CASE_NUM = FS.CASE_NUM
     AND
     (
         DC.SMS_PREF_SW = 'Y'
         OR DC.SMS_PREF_SW IS NULL
         OR DC.SMS_PREF_SW = ''
         OR DC.SMS_PREF_SW = ' '
     )
    INNER JOIN PHONE_ONE P1
      ON P1.CASE_NUM = FS.CASE_NUM
    INNER JOIN IE_APP_ONLINE.RT_PHONETYPES_MV RTP
      ON RTP.CODE = P1.PHN_TYPE_CD
    LEFT JOIN AUTH_REP_FLAG AR
      ON AR.CASE_NUM = FS.CASE_NUM
) A
WHERE NOT EXISTS
(
    SELECT 1
    FROM BKUP_TABLES.CASES_RIB183903_SMS B
    WHERE A.CASE_NUMBER = B.CASE_NUMBER
);

				
CREATE TABLE BKUP_TABLES.IMPACTED_CASES_RIB183903_SMS AS
WITH COUNTS AS (
    SELECT
        (SELECT COUNT(DISTINCT CASE_NUMBER) FROM BKUP_TABLES.CASES_RIB183903_SMS) AS TOTAL_COUNT,
        (SELECT COUNT(DISTINCT CASE_NUMBER) FROM BKUP_TABLES.CASES_RIB183903_SMS
         WHERE SMS_TRIGGERED IS NULL OR SMS_TRIGGERED = 'N') AS REMAINING_COUNT
    FROM DUAL
),
BATCH_INFO AS (
    SELECT
        CASE
            WHEN REMAINING_COUNT <= TOTAL_COUNT - 4 * FLOOR(TOTAL_COUNT / 5)
            THEN REMAINING_COUNT  -- Last run: pick ALL remaining
            ELSE FLOOR(TOTAL_COUNT / 5)  -- Runs 1-4: pick FLOOR(total/5)
        END AS PICK_COUNT
    FROM COUNTS
)
SELECT DISTINCT CASE_NUMBER
FROM (
    SELECT CASE_NUMBER,
           ROWNUM AS RN
    FROM (
        SELECT DISTINCT CASE_NUMBER
        FROM BKUP_TABLES.CASES_RIB183903_SMS
        WHERE SMS_TRIGGERED IS NULL OR SMS_TRIGGERED = 'N'
    )
)
WHERE RN <= (SELECT PICK_COUNT FROM BATCH_INFO);


INSERT INTO IE_APP_MRS_OWNER.CO_SMS_MASTER
(
    SMS_ID,
    SMS_DESCRIPTION,
    SMS_TEXT_EN,
    SMS_TEXT_PT,
    SMS_TEXT_ES,
    EFF_BEGIN_DT,
    EFF_END_DT,
    TEXT_CHAR_NUM_EN,
    TEXT_CHAR_NUM_PT,
    TEXT_CHAR_NUM_ES,
    TEXT_FREQUENCY,
    CATEGORY,   
    DYNAMIC_PARAM,
    HISTORY_SEQ,
    CREATE_USER_ID,
    CREATE_DT,
    UNIQUE_TRANS_ID,
    ARCHIVE_DT,
    UPDATE_USER_ID,
    UPDATE_DT,
    HIST_NAV_IND
)
SELECT
    (SELECT REPLACE(MAX(SMS_ID),SUBSTR(MAX(SMS_ID), -2),SUBSTR(MAX(SMS_ID), -2)+1) NEW_SMS FROM IE_APP_MRS_OWNER.CO_SMS_MASTER),
    'Manual SMS for HR1 changes',
    -- ==================== ENGLISH SMS TEXT ====================
    'RI Medicaid: A new federal law may end Medicaid for some non-U.S. citizens on Oct 1, 2026. Your SSI benefits are not affected. You may need to send documents to EOHHS by [DATE] to keep your coverage. Watch for a letter from RI in August. Call 211 or visit staycovered.ri.gov/updates for help.',

    -- ==================== PORTUGUESE SMS TEXT ====================
    'Medicaid de RI: Uma nova lei federal pode encerrar o Medicaid para alguns nao cidadaos dos EUA em 1 de out de 2026. Os seus beneficios de SSI nao serao afetados. Podera ter de enviar documentos a EOHHS ate [DATE] para manter a cobertura. Aguarde uma carta de RI em agosto. Ligue para o 211 ou visite staycovered.ri.gov/updates.',

    -- ==================== SPANISH SMS TEXT ====================
    'Medicaid de RI: Una nueva ley federal podria terminar con el Medicaid para algunos no ciudadanos el 1 de oct de 2026. Sus beneficios de SSI no se veran afectados. Es posible que deba enviar documentos a EOHHS antes del [FECHA] para mantener su cobertura. Espere una carta de RI en agosto. Llame al 211 o visite staycovered.ri.gov/updates.',
    TRUNC(SYSDATE),
    NULL,
   -- ==================== CHARACTER COUNTS ====================
    LENGTH('RI Medicaid: A new federal law may end Medicaid for some non-U.S. citizens on Oct 1, 2026. Your SSI benefits are not affected. You may need to send documents to EOHHS by [DATE] to keep your coverage. Watch for a letter from RI in August. Call 211 or visit staycovered.ri.gov/updates for help.'),

    LENGTH('Medicaid de RI: Uma nova lei federal pode encerrar o Medicaid para alguns nao cidadaos dos EUA em 1 de out de 2026. Os seus beneficios de SSI nao serao afetados. Podera ter de enviar documentos a EOHHS ate [DATE] para manter a cobertura. Aguarde uma carta de RI em agosto. Ligue para o 211 ou visite staycovered.ri.gov/updates.'),

    LENGTH('Medicaid de RI: Una nueva ley federal podria terminar con el Medicaid para algunos no ciudadanos el 1 de oct de 2026. Sus beneficios de SSI no se veran afectados. Es posible que deba enviar documentos a EOHHS antes del [FECHA] para mantener su cobertura. Espere una carta de RI en agosto. Llame al 211 o visite staycovered.ri.gov/updates.'),
    'One Time Manual SMS Request', 
    'One Time Manual SMS Request',
    'N',
    CO_SMS_MASTER_2SQ.NEXTVAL,
    'RIB-183903',
    (SELECT TO_DATE(PARAMETERS,'MM/DD/YYYY') FROM IE_APP_MRS_OWNER.FW_BATCH_PARAMETER_CONTROL WHERE JOB_ID = 'FW-GLOBL-DLY'),
    CO_SMS_MASTER_0SQ.NEXTVAL,
    TO_DATE('31-DEC-2999','DD-MON-YYYY'),
    NULL,
    NULL,
    'S'
FROM DUAL WHERE NOT EXISTS(SELECT 1 FROM IE_APP_MRS_OWNER.CO_SMS_MASTER WHERE CREATE_USER_ID = 'RIB-183903');

INSERT INTO IE_APP_MRS_OWNER.CO_SMS_MASTER_B
(
    SMS_ID,
    EFF_BEGIN_DT,
    EFF_END_DT,
    ARCHIVE_DT
)
SELECT 
    SMS_ID,
    (SELECT TO_DATE(PARAMETERS,'MM/DD/YYYY') FROM IE_APP_MRS_OWNER.FW_BATCH_PARAMETER_CONTROL WHERE JOB_ID = 'FW-GLOBL-DLY'),
    NULL,
    TO_DATE('31-DEC-2999','DD-MON-YYYY')
FROM IE_APP_MRS_OWNER.CO_SMS_MASTER WHERE CREATE_USER_ID = 'RIB-183903'
AND NOT EXISTS (SELECT 1 FROM IE_APP_MRS_OWNER.CO_SMS_MASTER CSM INNER JOIN IE_APP_MRS_OWNER.CO_SMS_MASTER_B CSMB ON CSM.SMS_ID = CSMB.SMS_ID AND CSM.CREATE_USER_ID = 'RIB-183903');

INSERT INTO IE_APP_ONLINE.CO_MAN_SMS_EMAIL_REQ
(
    MANUAL_REQ_SEQ,
    CASE_LIST,
    INDV_ID,
    SMS_ID,
    PROCESS_SW,
    PHN_NUM,
    REQUEST_DT,
    PROGRAM_CD,
    APP_NUM,
    AUTH_REP_ID,
    REQ_TYPE,
    TOA_LIST,
    MISC_PARAMS,
    ADD_PARAMS,
    TRIGGER_SOURCE,
    EMAIL_TMP_ID_EN,
    EMAIL_TMP_ID_ES,
    EMAIL_TMP_ID_PT,
    EMAIL_ID,
    AUTHREP_EM_REQ_SW,
    DYNAMIC_PARAM_SW,
    HISTORY_SEQ,
    CREATE_USER_ID,
    CREATE_DT,
    UNIQUE_TRANS_ID,
    ARCHIVE_DT,
    UPDATE_USER_ID,
    UPDATE_DT,
    USE_PHN,
	USE_EMAIL,
	PROVIDER_LIST,
	IS_MEDICAID	
)
SELECT 
    CO_MAN_SMS_EMAIL_REQ_1SQ.NEXTVAL,
    --(Select TO_CLOB(LISTAGG(CASE_NUM,',')) FROM BKUP_TABLES.IMPACTED_CASES_RIB183903_SMS) as CASE_LIST,
	I.CASE_NUMBER,
	NULL,
    (SELECT MAX(SMS_ID) FROM IE_APP_MRS_OWNER.CO_SMS_MASTER WHERE CREATE_USER_ID = 'RIB-183903'),  
    'N',
    NULL,
    (SELECT TO_DATE(PARAMETERS,'MM/DD/YYYY') FROM IE_APP_MRS_OWNER.FW_BATCH_PARAMETER_CONTROL WHERE JOB_ID = 'FW-GLOBL-DLY'),
    NULL,
    NULL,
    NULL,
    'S',
    NULL,
    NULL,
    NULL,
    'MANUAL',
    NULL,
    NULL,
    NULL,
    NULL,
    'N',
    'N',
    CO_MAN_SMS_EMAIL_REQ_0SQ.NEXTVAL,
    'RIB-183903',
    SYSDATE,
    CO_MAN_SMS_EMAIL_REQ_2SQ.NEXTVAL,
    TO_DATE('31-DEC-2999','DD-MON-YYYY'),
    NULL,
    NULL,
    'N',
	NULL,
	NULL,
	NULL
FROM (SELECT DISTINCT A.CASE_NUMBER FROM BKUP_TABLES.IMPACTED_CASES_RIB183903_SMS A) I;

UPDATE BKUP_TABLES.CASES_RIB183903_SMS A
SET
SMS_TRIGGERED = 'Y',
TRIGGERED_ON = (SELECT TO_DATE(PARAMETERS,'MM/DD/YYYY') FROM IE_APP_MRS_OWNER.FW_BATCH_PARAMETER_CONTROL WHERE JOB_ID = 'FW-GLOBL-DLY')
WHERE
(A.SMS_TRIGGERED IS NULL OR A.SMS_TRIGGERED ='N')
AND EXISTS (SELECT 1 FROM IE_APP_ONLINE.CO_MAN_SMS_EMAIL_REQ B WHERE TO_CHAR(B.CASE_LIST) = TO_CHAR(A.CASE_NUMBER) AND B.CREATE_USER_ID = 'RIB-183903')
;

--To populate master table storing information on whether the email , text or notice is sent.
UPDATE BKUP_TABLES.TRIGGER_INFO_183899 B
SET
B.SMS_TRIGGERED = 'Y',
B.SMS_TRIGGERED_DT = SYSDATE
WHERE 
NVL(B.SMS_TRIGGERED,'N') = 'N'
AND B.SMS_TRIGGERED_DT IS NULL
AND B.CASE_NUM IN (SELECT DISTINCT TO_NUMBER(C.CASE_LIST) CASE_NUM FROM IE_APP_ONLINE.CO_MAN_SMS_EMAIL_REQ C WHERE C.CREATE_USER_ID = 'RIB-183903' AND C.CREATE_DT >= TRUNC(SYSDATE-1))
;
