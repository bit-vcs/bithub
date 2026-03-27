///|
fn normalize_path(path : String) -> String {
  let mut p = path
  while p.length() > 0 && p.has_prefix("/") {
    p = String::unsafe_substring(p, start=1, end=p.length())
  }
  while p.length() > 0 && p.has_suffix("/") {
    p = String::unsafe_substring(p, start=0, end=p.length() - 1)
  }
  p
}

///|
fn is_markdown_path(path : String) -> Bool {
  path.has_suffix(".md") || path.has_suffix(".markdown")
}

///|
fn format_timestamp(raw : String) -> String {
  if raw.length() == 0 {
    return ""
  }
  let mut epoch = 0L
  for c in raw {
    if c >= '0' && c <= '9' {
      epoch = epoch * 10L + (c.to_int() - '0'.to_int()).to_int64()
    } else {
      return raw
    }
  }
  if epoch == 0L {
    return raw
  }
  // Convert epoch seconds to YYYY-MM-DD HH:MM UTC
  let secs_per_min = 60L
  let secs_per_hour = 3600L
  let secs_per_day = 86400L
  let remaining = epoch
  let time_of_day = remaining % secs_per_day
  let mut days = remaining / secs_per_day
  let hour = time_of_day / secs_per_hour
  let minute = (time_of_day % secs_per_hour) / secs_per_min
  // Calculate year/month/day from days since 1970-01-01
  let mut year = 1970L
  while true {
    let is_leap = (year % 4L == 0L && year % 100L != 0L) || year % 400L == 0L
    let year_days = if is_leap { 366L } else { 365L }
    if days < year_days {
      break
    }
    days -= year_days
    year += 1L
  }
  let is_leap = (year % 4L == 0L && year % 100L != 0L) || year % 400L == 0L
  let month_days = [
    31L, if is_leap { 29L } else { 28L }, 31L, 30L, 31L, 30L, 31L, 31L, 30L,
    31L, 30L, 31L,
  ]
  let mut month = 1L
  for md in month_days {
    if days < md {
      break
    }
    days -= md
    month += 1L
  }
  let day = days + 1L
  let pad2 = fn(n : Int64) -> String {
    if n < 10L {
      "0" + n.to_string()
    } else {
      n.to_string()
    }
  }
  year.to_string() +
  "-" +
  pad2(month) +
  "-" +
  pad2(day) +
  " " +
  pad2(hour) +
  ":" +
  pad2(minute) +
  " UTC"
}

///|
fn query_param(raw_path : String, key : String) -> String? {
  match query_string(raw_path) {
    None => None
    Some(query) => {
      for pair_view in query.split("&") {
        let pair = pair_view.to_string()
        if pair.length() == 0 {
          continue
        }
        match pair.find("=") {
          Some(i) => {
            let raw_key = String::unsafe_substring(pair, start=0, end=i)
            if @mars.url_decode(raw_key) == key {
              let raw_value = String::unsafe_substring(
                pair,
                start=i + 1,
                end=pair.length(),
              )
              return Some(@mars.url_decode(raw_value))
            }
          }
          None => {
            if @mars.url_decode(pair) == key {
              return Some("")
            }
          }
        }
      }
      None
    }
  }
}

///|
fn query_string(raw_path : String) -> String? {
  let query_pos = find_char(raw_path, '?')
  if query_pos < 0 {
    return None
  }
  let mut end = raw_path.length()
  let hash_pos = find_char(raw_path, '#')
  if hash_pos >= 0 && hash_pos > query_pos {
    end = hash_pos
  }
  let start = query_pos + 1
  if start >= end {
    Some("")
  } else {
    Some(String::unsafe_substring(raw_path, start~, end~))
  }
}

///|
fn strip_query_and_hash(path : String) -> String {
  let query_pos = find_char(path, '?')
  let hash_pos = find_char(path, '#')
  let mut end = path.length()
  if query_pos >= 0 && query_pos < end {
    end = query_pos
  }
  if hash_pos >= 0 && hash_pos < end {
    end = hash_pos
  }
  if end < path.length() {
    String::unsafe_substring(path, start=0, end~)
  } else {
    path
  }
}

///|
fn find_char(s : String, target : Char) -> Int {
  let mut idx = 0
  for c in s {
    if c == target {
      return idx
    }
    idx += 1
  }
  -1
}

///|
fn extract_json_string(json : Json, key : String) -> String {
  match json {
    Object(obj) =>
      match obj.get(key) {
        Some(String(s)) => s
        _ => ""
      }
    _ => ""
  }
}
