setMode -bscan
setCable -port auto
addDevice -p 1 -file audio_recorder.bit
program -p 1
saveCDF -file audio_recorder.cdf
quit
