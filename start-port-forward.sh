#!/bin/bash

echo "Stopping old port-forward processes..."

# Kill old port-forward processes
for port in 5000 4000 5433; do
    pid=$(lsof -t -i:$port || true)
    if [ ! -z "$pid" ]; then
        kill -9 $pid
        echo "Killed process on port $port"
    fi
done

echo "Starting port-forwarding in background..."

nohup /usr/local/bin/kubectl port-forward svc/backend 5000:5000 --address 0.0.0.0 > backend.log 2>&1 &
nohup /usr/local/bin/kubectl port-forward svc/frontend 4000:3000 --address 0.0.0.0 > frontend.log 2>&1 &
nohup /usr/local/bin/kubectl port-forward statefulset/database 5433:5432 --address 0.0.0.0 > database.log 2>&1 &

echo "Port forwarding started."
