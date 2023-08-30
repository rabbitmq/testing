## Stream Single Active Consumer Test

An example of how to trigger a rolling restart and check the post-restart status:

```
kubectl rollout restart sts main-s1000-server v3-11-18-s1000-server
kubectl wait --timeout=7200s --for=condition=Ready=false pod main-s1000-server-0 v3-11-18-s1000-server-0
kubectl wait --timeout=7200s --for=condition=Ready=true pod main-s1000-server-0 v3-11-18-s1000-server-0
sleep 60
kubectl exec -it main-s1000-server-0 -- rabbitmqctl list_stream_consumers
kubectl exec -it v3-11-18-s1000-server-0 -- rabbitmqctl list_stream_consumers
```
