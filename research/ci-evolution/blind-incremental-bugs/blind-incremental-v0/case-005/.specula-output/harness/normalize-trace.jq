def normalize_zxid:
  if . <= 0 then .
  else (((. / 4294967296) | floor) * 100 + (. % 4294967296))
  end;

.event.state.modelZxid = (.event.state.zxid | normalize_zxid)
