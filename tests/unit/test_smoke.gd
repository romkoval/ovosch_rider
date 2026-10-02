extends GutTest
## Дымовой тест инфраструктуры: проект открывается headless, GUT работает (REQ-INF-01, REQ-INF-02).

func test_project_boots() -> void:
	assert_eq(ProjectSettings.get_setting("application/config/name"), "ovosch-rider")
