"""Remove the original main completely and attach a diagnostic-only entrypoint."""
from pathlib import Path
import hashlib


def blob(raw):
    return hashlib.sha1(b'blob '+str(len(raw)).encode()+b'\0'+raw).hexdigest()


base=Path('reader.swift').read_bytes()
assert blob(base)=='fa8152abd137d8ccaeb32f12fac8cb65b319ff43'
marker=b'// MARK: - \xe3\x83\xa1\xe3\x82\xa4\xe3\x83\xb3\n'
assert base.count(marker)==1
prefix,tail=base.split(marker)
assert b'startCaptureServer()' in tail and b'recognitionMainLoop()' in tail
assert b'loadTeamFile()' in tail
support=Path('LiveShadowSupport.swift').read_bytes()
driver=Path('LiveShadowDriver.swift').read_bytes()
assert b'\nexit(trialMain())\n' in driver
# Only diagnostic path remains; legacy function bodies are unmodified.
Path('reader_live_trial.swift').write_bytes(prefix+b'\n'+support+b'\n'+driver)
print('TRIAL_BUILD: original production main removed')
