class_name Stages
## 5ステージの設定。Web版（three.js）の STAGES を Godot 向けに翻訳したもの。
##
## style   : sunflower / grass / festival / town
## cells   : 迷路のセル数（タイル数は cells*2+1）
## braid   : 行き止まりを減らす割合
## path_len: スタートから出口までの目標タイル数
## trans   : このステージへ切り替わるときのフェード色

static func all() -> Array:
	return [
		{
			"name": "ひまわり畑", "style": "sunflower", "cells": 9, "loops": 7, "braid": 0.12, "path_len": 51, "seed": 20260801,
			"deck": true, "eye": 1.55, "trans": Color(0.97, 0.98, 1.0),
			"sun_dir": Vector3(0.12, 0.88, 0.46), "sun_energy": 2.1, "sun_color": Color(1, 0.96, 0.87),
			"sky": {"zenith": Color(0.03, 0.17, 0.6), "mid": Color(0.13, 0.43, 0.92), "horizon": Color(0.6, 0.8, 1.0), "energy": 0.9, "overcast": 0.0, "cirrus": 0.0},
			"clouds": "cumulus", "fog": 0.0022, "fog_color": Color(0.7, 0.82, 1.0), "vol_fog": 0.006,
			"ambient": 1.0, "exposure": 1.0, "saturation": 1.15, "contrast": 1.08,
			"amb": {"cicada": 1.0, "wind": 0.12, "festival": 0.0, "crowd": 0.0, "rain": 0.0},
			"laugh": {"interval": Vector2(5.0, 8.0), "cutoff": 9000.0, "db": 0.0},
			"kimi_speed": 4.0, "wind": 0.16, "step": "dirt", "ground": 0, "birds": true, "insects": false,
		},
		{
			"name": "夏草", "style": "grass", "cells": 8, "loops": 3, "braid": 0.2, "path_len": 46, "seed": 7717 + 1093,
			"deck": false, "eye": 1.55, "trans": Color(0.96, 0.98, 1.0),
			"sun_dir": Vector3(0.62, 0.58, -0.28), "sun_energy": 1.9, "sun_color": Color(1, 0.92, 0.76),
			"sky": {"zenith": Color(0.05, 0.2, 0.58), "mid": Color(0.18, 0.46, 0.86), "horizon": Color(0.7, 0.82, 0.92), "energy": 0.95, "overcast": 0.0, "cirrus": 0.15},
			"clouds": "cumulus_low", "fog": 0.0035, "fog_color": Color(0.76, 0.84, 0.9), "vol_fog": 0.009,
			"ambient": 0.95, "exposure": 1.0, "saturation": 1.1, "contrast": 1.06,
			"amb": {"cicada": 0.8, "wind": 0.35, "festival": 0.0, "crowd": 0.0, "rain": 0.0},
			"laugh": {"interval": Vector2(6.5, 9.5), "cutoff": 7000.0, "db": -1.0},
			"kimi_speed": 4.0, "wind": 0.3, "step": "grass", "ground": 0, "birds": true, "insects": true,
		},
		{
			"name": "夏祭り", "style": "festival", "cells": 8, "loops": 4, "braid": 0.3, "path_len": 48, "seed": 7717 + 1093 * 2,
			"deck": false, "eye": 1.3, "trans": Color(1.0, 0.85, 0.63),
			"sun_dir": Vector3(0.9, 0.12, -0.42), "sun_energy": 0.9, "sun_color": Color(1, 0.62, 0.35),
			"sky": {"zenith": Color(0.06, 0.09, 0.24), "mid": Color(0.35, 0.3, 0.5), "horizon": Color(0.95, 0.56, 0.32), "energy": 0.8, "overcast": 0.0, "cirrus": 0.5},
			"clouds": "dusk", "fog": 0.009, "fog_color": Color(0.36, 0.3, 0.42), "vol_fog": 0.012,
			"ambient": 0.75, "exposure": 1.05, "saturation": 1.12, "contrast": 1.1,
			"amb": {"cicada": 0.12, "wind": 0.05, "festival": 0.8, "crowd": 0.6, "rain": 0.0},
			"laugh": {"interval": Vector2(8.0, 12.0), "cutoff": 5000.0, "db": 0.0},
			"kimi_speed": 3.8, "wind": 0.05, "step": "dirt", "ground": 1, "birds": false, "insects": false,
		},
		{
			"name": "夕立", "style": "town", "cells": 7, "loops": 3, "braid": 0.3, "path_len": 40, "seed": 7717 + 1093 * 3,
			"deck": false, "eye": 1.55, "trans": Color(0.09, 0.11, 0.14),
			"sun_dir": Vector3(0.4, 0.5, -0.6), "sun_energy": 0.35, "sun_color": Color(0.62, 0.69, 0.76),
			"sky": {"zenith": Color(0.13, 0.16, 0.2), "mid": Color(0.22, 0.26, 0.3), "horizon": Color(0.3, 0.34, 0.38), "energy": 0.6, "overcast": 1.0, "cirrus": 0.0},
			"clouds": "none", "fog": 0.02, "fog_color": Color(0.16, 0.19, 0.22), "vol_fog": 0.015,
			"ambient": 0.7, "exposure": 0.95, "saturation": 0.78, "contrast": 1.1,
			"amb": {"cicada": 0.0, "wind": 0.4, "festival": 0.0, "crowd": 0.0, "rain": 1.0},
			"laugh": {"interval": Vector2(11.0, 17.0), "cutoff": 3200.0, "db": 1.0},
			"kimi_speed": 3.6, "wind": 0.12, "step": "wet", "ground": 2, "birds": false, "insects": false,
			"rain": true,
		},
		{
			"name": "夏の終わり", "style": "sunflower", "cells": 7, "loops": 4, "braid": 0.4, "path_len": 38, "seed": 7717 + 1093 * 4,
			"deck": false, "eye": 1.55, "trans": Color(1.0, 0.75, 0.54),
			"droop": true, "fade": true, "finale": true,
			"sun_dir": Vector3(-0.3, 0.66, 0.6), "sun_energy": 1.5, "sun_color": Color(1, 0.95, 0.86),
			"sky": {"zenith": Color(0.16, 0.36, 0.66), "mid": Color(0.36, 0.58, 0.84), "horizon": Color(0.86, 0.9, 0.93), "energy": 0.95, "overcast": 0.0, "cirrus": 0.9},
			"clouds": "none", "fog": 0.004, "fog_color": Color(0.88, 0.9, 0.92), "vol_fog": 0.004,
			"ambient": 1.0, "exposure": 1.0, "saturation": 0.8, "contrast": 1.02,
			"amb": {"cicada": 0.08, "wind": 0.6, "festival": 0.0, "crowd": 0.0, "rain": 0.0},
			"laugh": {"interval": Vector2(999.0, 999.0), "cutoff": 3200.0, "db": -2.0},
			"kimi_speed": 3.2, "wind": 0.22, "step": "grass", "ground": 0, "birds": true, "insects": true,
		},
	]
