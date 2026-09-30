bind_socket = "127.0.0.1:11332";
count = 1;
milter = yes;
timeout = 30s;
max_retries = 1;
discard_on_reject = false;
quarantine_on_reject = false;
upstream "local" {
  default = yes;
  self_scan = yes;
}
