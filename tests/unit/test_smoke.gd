extends GutTest

func test_project_boots() -> void:
	assert_eq(ProjectSettings.get_setting("application/config/name"), "ovosch-rider")
