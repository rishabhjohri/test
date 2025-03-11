import time
import numpy as np

# Simulated workload: Heavy matrix computation
def cpu_intensive_task():
    print(" Running heavy computation...")
    
    size = 3000  # Increase size for more load
    matrix_a = np.random.rand(size, size)
    matrix_b = np.random.rand(size, size)

    # Simulate heavy computation
    result = np.matmul(matrix_a, matrix_b)
    
    print("✔ Computation completed!")

if __name__ == "__main__":
    start_time = time.time()
    cpu_intensive_task()
    end_time = time.time()
    
    print(f" Execution Time: {end_time - start_time:.2f} seconds")
