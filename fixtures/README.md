# Fixtures

**All fixtures in this directory are synthetic.** No real patient data is
stored in this repository, and none may be.

`sample-transcript.txt` is a fictional GP consultation used to exercise the
rule-based generator. It deliberately contains:

- a clear SOAP structure (history, examination, impression, plan),
- role prefixes (`CLINICIAN:`, `PATIENT:`) to exercise `parse_transcript_text`,
- one deliberately unmatchable closing remark ("the parking situation…") to
  prove the generator reports unfiled statements instead of silently dropping
  them.

Do not add real recordings, transcripts or notes here. Validation recordings
belong outside the repository, in an encrypted volume, under the retention
rules in `docs/compliance/PRIVACY.md`.
