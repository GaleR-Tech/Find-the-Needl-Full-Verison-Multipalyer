extends RefCounted

const STEAM_APP_ID := "5160800"
const SUPPORTED_BUILD := "26547680"
const BUILD_TOOL := 9

const REQUIRED := [
	"snapshot_capture", "snapshot_restore", "action_capture", "host_apply",
	"guest_mutation_guard", "machine_host_only", "player_pose", "isolated_guest_session", "host_save",
]

static func supports_build(build: String) -> bool:
	return build == SUPPORTED_BUILD

func required_capabilities() -> PackedStringArray:
	return PackedStringArray(REQUIRED)

func verified_evidence(build: String) -> Dictionary:
	if not supports_build(build):
		return {}
	var evidence := {}
	for capability in REQUIRED:
		evidence[capability] = true
	return evidence

func check_evidence(evidence: Dictionary) -> Dictionary:
	for capability in REQUIRED:
		if evidence.get(capability) != true:
			return {"ok": false, "code": "CAPABILITY_MISSING", "value": null}
	return {"ok": true, "code": "OK", "value": evidence.duplicate()}
