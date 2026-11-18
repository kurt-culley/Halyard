# Behaviour changes from the original tool

The wire format and file formats match the original tool byte for byte; the golden vectors prove it. Behaviour around
them changes where the original was unsafe or accidental. Each change has a test that states the new behaviour.

| Area | Original | Halyard | Why |
|---|---|---|---|
| Reply checksum | A reply with a bad checksum could still answer a request | Only frames with a good checksum answer requests | A corrupted reply must never confirm a write |
| Batches | A batch kept sending after an unanswered write, including the flash store | A batch stops at the first request that fails; the rest are not sent | Never store what the ECU didn't acknowledge |
| Request timing | The queue moved on after 2 s while the caller waited 3 s, so a late reply could be matched to the next request | One timeout per request; the next request waits | Replies can't be matched to the wrong request |
| Read-only mode | Host answers (including firmware data) always passed the bench guard | Only listed read requests and the lifesign pass; host answers never do | Firmware transfer is a write |
| Timeouts | Fixed for a cable | Per link kind; Wi-Fi bridges get longer timeouts | Bridges add latency |
| Live-data layout | Kept across reconnects | Reset on each connection; the session asks for it again | No stale layout after a reconnect |
| Identity text | UTF-8 decoding stripped a leading byte-order mark in the TypeScript port | Kept as U+FEFF, as the original did | Matches the original |
| Definition member order | A table's values read before its size, or a driver's link ids before their count, were silently dropped | Values are read whatever the order, then fitted to the size | The order of elements in a file shouldn't change its meaning |
| Identity replies | Any identity reply started the connect sequence, one with a failure status included (it then found no definition and dropped the calibration) | Only a successful identity reply starts it | A failed reply says nothing about which ECU is there |
| Password and hash replies | A password-state reply at any time re-read every table and driver; a hash reply at any time read whatever differed, and turned reporting on | Only the replies the connect sequence asked for do this | A password screen or a hash check later in the session must not start a full read |
| Fahrenheit input | A value entered in Fahrenheit went to the ECU as (F + 32) / 1.8, 35.6 °C too warm | (F − 32) / 1.8 | A wrong conversion writes a wrong temperature to the ECU |
