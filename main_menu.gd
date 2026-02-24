class_name MainMenu
extends Control

const MAIN_SCENE := "res://main.tscn"


func _ready() -> void:
	$VBoxContainer/StartButton.grab_focus()


func _on_start_button_pressed() -> void:
	get_tree().change_scene_to_file(MAIN_SCENE)


func _on_quit_button_pressed() -> void:
	get_tree().quit()
