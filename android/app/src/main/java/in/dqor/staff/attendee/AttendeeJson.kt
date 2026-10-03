package `in`.dqor.staff.attendee

import org.json.JSONArray
import org.json.JSONObject
import org.json.JSONTokener

internal class AttendeeJson(private val text: String) {
    private var position = 0
    private var nodes = 0
    private fun invalid(): Nothing = throw AttendeeFailure(AttendeeProblem.INVALID_RESPONSE)
    private fun whitespace() { while (position < text.length && text[position] in " \t\r\n") position++ }
    private fun take(char: Char): Boolean { whitespace(); if (position < text.length && text[position] == char) { position++; return true }; return false }
    fun parse(): JSONObject {
        val result = value(0) as? JSONObject ?: invalid()
        whitespace(); if (position != text.length) invalid()
        return result
    }
    private fun value(depth: Int): Any {
        whitespace(); if (depth > 12 || ++nodes > 2000 || position >= text.length) invalid()
        return when (text[position]) {
            '{' -> {
                position++; val result = JSONObject(); val keys = mutableSetOf<String>()
                if (!take('}')) while (true) {
                    whitespace(); if (position >= text.length || text[position] != '"') invalid()
                    val key = string(); if (!keys.add(key) || !take(':')) invalid()
                    result.put(key, value(depth + 1))
                    if (take('}')) break
                    if (!take(',')) invalid()
                }
                result
            }
            '[' -> {
                position++; val result = JSONArray()
                if (!take(']')) while (true) {
                    result.put(value(depth + 1)); if (take(']')) break; if (!take(',')) invalid()
                }
                result
            }
            '"' -> string()
            't' -> literal("true", true)
            'f' -> literal("false", false)
            'n' -> literal("null", JSONObject.NULL)
            else -> {
                val start = position
                while (position < text.length && text[position] in "0123456789.eE+-") position++
                val number = text.substring(start, position)
                if (!number.matches(Regex("-?(0|[1-9][0-9]*)(\\.[0-9]+)?([eE][+-]?[0-9]+)?"))) invalid()
                if ('.' !in number && 'e' !in number && 'E' !in number) {
                    val long = number.toLongOrNull() ?: invalid()
                    if (long in Int.MIN_VALUE..Int.MAX_VALUE) long.toInt() else long
                } else number.toDoubleOrNull()?.takeIf { it.isFinite() } ?: invalid()
            }
        }
    }
    private fun literal(literal: String, value: Any): Any {
        if (!text.startsWith(literal, position)) invalid(); position += literal.length; return value
    }
    private fun string(): String {
        val start = position++
        while (position < text.length) {
            val char = text[position++]
            if (char == '"') return JSONTokener(text.substring(start, position)).nextValue() as? String ?: invalid()
            if (char.code < 32) invalid()
            if (char == '\\') {
                if (position >= text.length) invalid()
                when (text[position++]) {
                    '"', '\\', '/', 'b', 'f', 'n', 'r', 't' -> Unit
                    'u' -> {
                        if (position + 4 > text.length || text.substring(position, position + 4).any { it !in "0123456789abcdefABCDEF" }) invalid()
                        position += 4
                    }
                    else -> invalid()
                }
            }
        }
        invalid()
    }
}
