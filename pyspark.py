
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
