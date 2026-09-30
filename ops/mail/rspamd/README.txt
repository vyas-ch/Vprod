Validated staging configuration — NOT INSTALLED

Target: Ubuntu resolute Rspamd 3.8.1-1.2ubuntu3 amd64, candidate from the configured TransIP Ubuntu mirror.
Package SHA256: afb56c47e71658d0ea5f25f34728d3497e5e0bda40d3d2cab695257bf6c250d5

Install only rspamd.conf.override and local.d/*.conf / local.d/*.inc under /etc/rspamd after backing up existing files. Keep stock package config. Run rspamadm configtest --strict again in the real installed environment before activation.

One loopback Milter proxy worker scans directly. Normal, controller and fuzzy-storage workers are disabled. No Redis or antivirus process is required. The config retains SPF, inbound DKIM verification, DMARC, RBL, MIME/header and regexp checks. Conservative initial actions are add-header at6/reject at20, no greylisting or subject rewrite, and no silent discard. Spam headers still require a deliberate Dovecot Sieve policy if messages should be moved to Junk. No attachment malware-scanning guarantee.

Bayes is disabled by classifier = {}; null fails on this package. No learned statistical model, neural training or external fuzzy checks. bayes_expiry can still appear in the module list because its Lua file registers an on_load callback; the packaged callback immediately returns outside the primary controller, and there are no classifiers/controller in this configuration. No Redis calls or expiry tasks can be scheduled by that callback. Do not treat local.d/bayes_expiry.conf enabled=false as proven functional on3.8.1: it has no stock include.

The package's DKIM signing module is separate from DKIM verification. This template supplies no signing key, selector or mail credentials. Installer must provision and test outbound DKIM separately if required; do not claim signing merely because dkim_signing appears loaded.

Self-scan proxy3.8.1 has no max_tasks option. Bound incoming SMTP and submission concurrency in Postfix; for example2 public SMTP processes plus1 submission process is at most3 simultaneous smtpd sessions reaching the scanner. Choose counts against actual measured memory. An alternative normal count1/max_tasks2 plus forwarding proxy count1 enforces a scanner-specific cap and provides a local HTTP scanning endpoint, but adds a process. Never leave both self-scan and a normal scanner active unintentionally.

max_message16M is paired with Postfix message_size_limit15728640 (15MiB whole encoded message) and at most20 envelope recipients. Milter content timeout must exceed scanning timeout10s. On scanner errors require Postfix milter_default_action=tempfail; do not use accept as a fallback.

Validation used extracted .debs in /home/vyas/vprod-mail-research-rspamd-20261001, not a package install. Exact package checksums were compared with apt metadata before extraction. Missing runtime shared libraries were similarly downloaded and extracted (libluajit, common files, libhyperscan). All path overrides stay in that unprivileged directory. No daemon was started, no ports were opened, no service or firewall was modified. The pre-init 'cannot open ... /var/lib/rspamd/hsmp...' warning occurs before path overrides in this unpacked-only run; real installation must provide the normal writable cache directory for _rspamd. It is not an unresolved UCL/syntax error.

Syntax validation does not establish RAM fit, real scanning, deliverability, authentication or protection against open relay. Those remain installer/activation checks. Retain fail-closed filtering once active, and stage Postfix without claiming spam filtering until these tests pass.

Official references:
https://docs.rspamd.com/workers/rspamd_proxy/
https://docs.rspamd.com/workers/normal/
https://docs.rspamd.com/configuration/options/
https://docs.rspamd.com/configuration/statistic/
https://raw.githubusercontent.com/rspamd/rspamd/3.8.1/src/rspamd_proxy.c
https://www.postfix.org/MILTER_README.html
