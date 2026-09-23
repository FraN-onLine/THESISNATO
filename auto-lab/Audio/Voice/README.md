# HOW TO ADD NEW VOICE CLIPS (no code changes needed):
#   1. Drop a recorded line as res://Audio/Voice/<line_id>.ogg
#      (find each line_id in the caption shown in-game, or in voice.get_script_log()).
#   2. Point the lesson voice at that folder once:
#        voice.set_clip_root("res://Audio/Voice")
#      then every matching line plays audio automatically.
# Example layout (create the folder; it is git-ignored until you add clips):
#   Audio/Voice/
#     checkpoint_sim_trace_1.ogg
#     def_5tuple.ogg
#     README.md  <- this file
