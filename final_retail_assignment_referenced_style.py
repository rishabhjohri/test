# Step 1: Setup SparkSession
from pyspark.sql import SparkSession
from pyspark.sql.functions import (
    col, trim, sum, avg, countDistinct, rank, lag,
    date_format, expr, broadcast, count, upper, lit, udf
)
from pyspark.sql.window import Window
from pyspark.sql.types import StringType

spark = SparkSession.builder     .appName("OnlineRetailAssignment")     .getOrCreate()

# Step 2: Create Toy DataFrames (replace with CSV in real case)
import pandas as pd
import random
from datetime import datetime, timedelta

customer_ids = list(range(1, 11))
names = [f"Customer_{i}" for i in customer_ids]
countries = random.choices(['USA', 'UK', 'Germany', 'France', 'India'], k=10)
ages = random.choices(range(18, 70), k=10)
genders = random.choices(['Male', 'Female'], k=10)

customers_df = pd.DataFrame({
    'customer_id': customer_ids,
    'name': names,
    'country': countries,
    'age': ages,
    'gender': genders
})

order_ids = list(range(100, 120))
products = ['Laptop', 'Smartphone', 'Tablet', 'Monitor', 'Keyboard']
categories = ['Electronics', 'Electronics', 'Electronics', 'Accessories', 'Accessories']
order_data = []
for i in order_ids:
    cust_id = random.choice(customer_ids)
    prod_idx = random.randint(0, len(products) - 1)
    quantity = random.randint(1, 5)
    price = round(random.uniform(50, 1000), 2)
    date = datetime(2023, 1, 1) + timedelta(days=random.randint(0, 365))
    order_data.append([i, cust_id, products[prod_idx], categories[prod_idx], quantity, price, date.strftime("%Y-%m-%d")])

orders_df = pd.DataFrame(order_data, columns=['order_id', 'customer_id', 'product', 'category', 'quantity', 'price', 'order_date'])

# Step 3: Load into Spark DataFrames
customers_sdf = spark.createDataFrame(customers_df)
orders_sdf = spark.createDataFrame(orders_df)

# Print schemas and sample data
customers_sdf.printSchema()
orders_sdf.printSchema()
customers_sdf.show(10)
orders_sdf.show(10)

# Step 4: Create Temp Views
customers_sdf.createOrReplaceTempView("customers")
orders_sdf.createOrReplaceTempView("orders")

# Step 5: Data Cleaning
customers_clean = customers_sdf.dropDuplicates().na.drop()
orders_clean = orders_sdf.dropDuplicates().na.drop()

for col_name in ['name', 'country', 'gender']:
    customers_clean = customers_clean.withColumn(col_name, trim(col(col_name)))
for col_name in ['product', 'category']:
    orders_clean = orders_clean.withColumn(col_name, trim(col(col_name)))

customers_clean = customers_clean.withColumn("age", col("age").cast("int"))
orders_clean = orders_clean.withColumn("price", col("price").cast("double"))     .withColumn("order_date", col("order_date").cast("date"))

# Step 6: EDA
customers_clean.groupBy("country").count().show()
customers_clean.groupBy("age").count().orderBy("age").show()
customers_clean.groupBy("country").count().orderBy(col("count").desc()).show(5)
orders_clean.groupBy("category").count().orderBy(col("count").desc()).show(5)

# Step 7: DataFrame API Insights
orders_clean = orders_clean.withColumn("revenue", col("price") * col("quantity"))

orders_clean.groupBy("category").agg(sum("revenue").alias("total_revenue")).show()

orders_with_country = orders_clean.join(customers_clean, "customer_id")
orders_with_country.withColumn("order_value", col("price") * col("quantity"))     .groupBy("country").agg(avg("order_value").alias("avg_order_value")).show()

orders_clean.groupBy("customer_id").agg(sum("revenue").alias("total_revenue"))     .orderBy(col("total_revenue").desc()).show(10)

orders_clean.select("product").distinct().count()
orders_clean.groupBy("product").agg(sum("quantity").alias("total_quantity"))     .orderBy(col("total_quantity").desc()).show(1)

# Step 8: SQL Insights
spark.sql("""
    SELECT category, SUM(quantity) AS total_quantity, SUM(price * quantity) AS total_revenue
    FROM orders
    GROUP BY category
""").show()

spark.sql("""
    SELECT customer_id, SUM(price * quantity) AS total_spent
    FROM orders
    GROUP BY customer_id
    ORDER BY total_spent DESC
    LIMIT 1
""").show()

spark.sql("""
    SELECT DATE_FORMAT(order_date, 'yyyy-MM') AS month, SUM(price * quantity) AS monthly_revenue
    FROM orders
    GROUP BY month
    ORDER BY month
""").show()

spark.sql("""
    SELECT customer_id, COUNT(DISTINCT product) AS distinct_products
    FROM orders
    GROUP BY customer_id
    HAVING COUNT(DISTINCT product) > 5
""").show()

# Step 9: Joins and Group Aggregates
enriched_orders = orders_clean.join(customers_clean, "customer_id")

customers_with_orders = customers_clean.join(orders_clean, "customer_id", "left")
customers_with_orders.filter(col("order_id").isNull()).select("customer_id", "name").show()

enriched_orders = enriched_orders.withColumn("revenue", col("price") * col("quantity"))
enriched_orders.groupBy("country").agg(sum("revenue").alias("total_revenue")).show()

enriched_orders.groupBy("country", "customer_id").agg(sum("revenue").alias("cust_rev"))     .groupBy("country").agg(avg("cust_rev").alias("avg_rev_per_cust")).show()

windowSpec = Window.partitionBy("country").orderBy(col("revenue").desc())
enriched_orders.groupBy("country", "customer_id").agg(sum("revenue").alias("revenue"))     .withColumn("rank", rank().over(windowSpec)).filter(col("rank") == 1).show()

# Step 10: Window Functions
rev_cust = enriched_orders.groupBy("country", "customer_id").agg(sum("revenue").alias("total_revenue"))
win = Window.partitionBy("country").orderBy(col("total_revenue").desc())
rev_cust.withColumn("rank", rank().over(win)).filter(col("rank") <= 3).show()

monthly_rev = orders_clean.withColumn("month", date_format("order_date", "yyyy-MM"))     .groupBy("month").agg(sum("revenue").alias("monthly_revenue"))     .orderBy("month")

monthly_rev.withColumn("prev_month_revenue", lag("monthly_revenue", 1).over(Window.orderBy("month")))     .withColumn("change", col("monthly_revenue") - col("prev_month_revenue"))     .show()

# Step 11: Deliverables - Save Files
orders_clean.write.mode("overwrite").parquet("output/final_cleaned_orders.parquet")

country_revenue = enriched_orders.groupBy("country").agg(sum("revenue").alias("total_revenue"))
country_revenue.write.mode("overwrite").option("header", True).csv("output/country_revenue_summary.csv")

# Step 12: Bonus Tasks

# Median using expr
orders_clean.withColumn("order_value", col("price") * col("quantity"))     .select(expr("percentile_approx(order_value, 0.5)").alias("median_order_value")).show()

# Broadcast Join
broadcast_orders = orders_clean.join(broadcast(customers_clean), "customer_id")
broadcast_orders.groupBy("country").agg(sum("price" * col("quantity")).alias("broadcast_revenue")).show()

# Accumulator
acc = spark.sparkContext.accumulator(0)
def count_sales(row):
    acc.add(1)
    return row
orders_clean.rdd.map(count_sales).count()
print("Total records processed:", acc.value)
