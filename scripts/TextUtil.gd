class_name TextUtil
extends RefCounted

# 표시용 텍스트 유틸.
#
# keep_all — 한글 어절 단위 줄바꿈(2026-08-21 사용자 "'조여옵니/다'처럼 음절이 꺾인다"):
# Godot(ICU) 줄바꿈은 한글 음절 사이를 전부 줄바꿈 후보로 봐서 AUTOWRAP_WORD_SMART로도
# 어절이 깨진다. 로케일 태그(ko-u-lw-keepall)는 4.6에서 무시됨(실측) → WORD JOINER(U+2060)를
# 공백/개행이 아닌 인접 문자 사이에 삽입해 줄바꿈 후보를 어절 경계(공백)로 한정한다.
# ⚠ 표시 직전의 라벨 텍스트에만 쓸 것 — 비교·검색·저장 문자열에 쓰면 원문과 달라진다.
static func keep_all(s: String) -> String:
	var wj: String = char(0x2060)
	var out: String = ""
	for i in s.length():
		var c: String = s[i]
		out += c
		if i + 1 < s.length():
			var n: String = s[i + 1]
			if c != " " and c != "\n" and n != " " and n != "\n":
				out += wj
	return out
