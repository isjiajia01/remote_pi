// Tests must not inherit the invoking Pi's room identity: running the suite
// from a pi-subagents child (PI_SUBAGENT_CHILD=1) or a phone session would
// otherwise change every derived room id. Tests that need these stub them.
for (const key of ["PI_SUBAGENT_CHILD", "PI_SUBAGENT_PARENT_SESSION", "PERCH_ROOM_ID", "PERCH_SESSION_ID"]) {
  delete process.env[key];
}
