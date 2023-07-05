Measure the impact of message embedding vs message store.

Classic queues store small messages differentaly than large messages.
With v1, small message (up to `queue_index_embed_msgs_below` in size, 4096B by default)
are embedded in the queue index. With v2, they are stored in a per-queue message store.

Messages above that threshold are stored in a per-vhost message store.

This test modifies the templates and scenario files. In most tests, the same message sizes
are applied to all the configurations. In this case, this doesn't really make sense - what we
want are message sizes just below and just above the threshold. Therfore, we define different
thresholds and then deploy two environments for each of them - 10 bytes below and 10 bytes
above the threshold. To make it work, there is also a hardcoded `* 2` multiplication for
the number of environments (so that all perf-test instances start at the same time).
