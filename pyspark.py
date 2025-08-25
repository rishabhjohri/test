
# Step 1: Create SparkSession
from pyspark.sql import SparkSession
spark = SparkSession.builder \
    .appName("SalesAnalysis") \
    .getOrCreate()

# Step 2: Load the Data
df = spark.read.csv("sales.csv", header=True, inferSchema=True)

# Step 3: Basic Exploration
print("Total records:", df.count())
df.select("Product").distinct().show()

# Step 4: Convert to RDD
sales_rdd = df.rdd

# Step 5: Transformations and Actions
# Aggregate sales for each product
product_sales = sales_rdd.map(lambda row: (row['Product'], row['Amount'])) \
                         .reduceByKey(lambda x, y: x + y)

# Step 6: Persist the Results
product_sales.persist()
print("Number of products:", product_sales.count())

# Step 7: DataFrame API (Optional for Practice)
from pyspark.sql import functions as F
df_sales = df.groupBy("Product").agg(F.sum("Amount").alias("TotalSales"))
df_sales.show()

# Step 8: Observe DAG and Lineage
# Go to Spark UI (usually http://localhost:4040) in your browser
# Check Jobs and Stages, click DAG Visualization for your job, observe lineage


#--------------------------------------------------------------------------------#

# Step 9: Broadcast and Accumulator (Optional Add-on)

# Broadcast a list of premium products
premium_products = ["Laptop", "Camera", "Smartwatch"]
broadcast_premium = spark.sparkContext.broadcast(premium_products)

# Accumulator to count total sales processed
sales_accum = spark.sparkContext.accumulator(0)

# Filter for premium products and count sales
premium_sales = sales_rdd.filter(
    lambda row: row['Product'] in broadcast_premium.value
).map(
    lambda row: (row['Product'], row['Amount'])
)

# Increment accumulator for each sale processed
def count_sales(row):
    sales_accum.add(1)
    return row

premium_sales_counted = premium_sales.map(count_sales)

# Aggregate sales for premium products
premium_sales_agg = premium_sales_counted.reduceByKey(lambda x, y: x + y)
premium_sales_agg.persist()

# Show results
print("Total premium sales processed:", sales_accum.value)
print("Premium product sales totals:")
for product, total in premium_sales_agg.collect():
    print(product, total)

# Step 10: Save Output

# Save RDD output as text file
premium_sales_agg.saveAsTextFile("premium_product_sales_output")

# Save DataFrame output as CSV (for DataFrame API)
df_sales.write.csv("product_sales_output", header=True)



import findspark
findspark.init()

from pyspark.sql import SparkSession

spark = SparkSession.builder \
    .appName("PySparkSQL_Lab") \
    .getOrCreate()

print(spark.version)
#####################################3----------------------------------------------------------------------------#################33
# Load Employees.csv
employees_df = spark.read.csv("Employees.csv", header=True, inferSchema=True)

# Display first 5 rows
employees_df.show(5)
employees_df.printSchema()

# Load Sales.csv
sales_df = spark.read.csv("Sales.csv", header=True, inferSchema=True)
sales_df.show(5)
sales_df.printSchema()

##-----------------------------------------------------------------------##
# Select specific columns
employees_df.select("name", "salary").show(5)

# Filter employees with salary > 50000
employees_df.filter(employees_df.salary > 50000).show()

# Count employees by department
employees_df.groupBy("department").count().show()

# Task 1: Find employees in IT department
it_employees_df = employees_df.filter(employees_df.department == "IT")
it_employees_df.show()

# Task 2: Count employees per location
employees_by_location_df = employees_df.groupBy("location").count()
employees_by_location_df.show()

###=====================================================================
#----------------------------------------------------------------------
employees_df.createOrReplaceTempView("employees")

# Top 5 highest-paid employees
spark.sql("""
SELECT name, department, salary
FROM employees
ORDER BY salary DESC
LIMIT 5
""").show()

# Average salary per department
spark.sql("""
SELECT department, ROUND(AVG(salary),2) as avg_salary
FROM employees
GROUP BY department
""").show()

# SQL query to list employees whose salary is between 40,000 and 60,000
spark.sql("""
SELECT name, department, salary
FROM employees
WHERE salary BETWEEN 40000 AND 60000
""").show()

#####################+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
joined_df = employees_df.join(
    sales_df,
    employees_df.employee_id == sales_df.employee_id,
    "inner"
)

# Total sales amount by department
joined_df.groupBy("department").sum("amount").show()

# Task 1: Find top-selling employee by sales amount
top_selling_employee_df = joined_df.groupBy("employee_id", "name") \
    .sum("amount") \
    .withColumnRenamed("sum(amount)", "total_sales") \
    .orderBy("total_sales", ascending=False) \
    .limit(1)

top_selling_employee_df.show()

# Task 2: Show total sales per location
sales_per_location_df = joined_df.groupBy("location") \
    .sum("amount") \
    .withColumnRenamed("sum(amount)", "total_sales")

sales_per_location_df.show()
