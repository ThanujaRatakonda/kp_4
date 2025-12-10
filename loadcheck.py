import requests  # send http get requests
import concurrent.futures  # send request parallel for load testing
import time   #measure execu. time
# url from minikube service ingress-nginx-controller -n ingress-nginx --url-> url for load testing
URL = "http://192.168.49.2:30987/users"   
def hit(i):  #send one GET request
    try:
        r = requests.get(URL, timeout=5) 
        pod = r.headers.get("X-Pod-Name", "unknown-pod")  # reades X-pod name added by FastApi middleware
        elapsed = r.elapsed.total_seconds()   # calculate how long responce took
        return i, pod, elapsed    
    except Exception:
        return i, "ERR-POD", None
def main():
    total = int(input("Number of requests: "))  
    start_time = time.time() # time start
    results = []
    # ThreadPoolExecutor for concurrency create threspool with 50 parller workers
    # submits all requests to execute at same time
    with concurrent.futures.ThreadPoolExecutor(max_workers=50) as executor:
        futures = [executor.submit(hit, i+1) for i in range(total)] 
        # wait for each request to complete and store result
        for f in concurrent.futures.as_completed(futures):
            results.append(f.result())
    # Count requests per pod  -> which pod handeled which request 
    pod_count = {}
    for i, pod, elapsed in results:
        print(f"Request {i}: served by {pod} (time: {elapsed}s)")
        pod_count[pod] = pod_count.get(pod, 0) + 1  # total count per pod
    print("\n--- ACTUAL POD HIT COUNT ---")
    for pod, count in pod_count.items():
        print(f"{pod}: {count} requests")   # show how load was distributed to
    print(f"\nTotal time: {time.time() - start_time:.3f}s")  #total time
if __name__ == "__main__":
    main()
