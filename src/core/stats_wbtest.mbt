///| Whitebox tests for stats functions in api_state.mbt
///| These tests can access private functions.

///|
fn test_storage() -> &Storage {
  MapStorage::new()
}

///|
test "count_files: empty storage returns 0" {
  let s = test_storage()
  let count = count_files(s, "")
  inspect(count, content="0")
}

///|
test "count_files: single file returns 1" {
  let s = test_storage()
  s.set_string("file.txt", "content")
  let count = count_files(s, "")
  inspect(count, content="1")
}

///|
test "count_files: files in subdirectories are counted" {
  let s = test_storage()
  s.set_string("dir1/file1.txt", "content1")
  s.set_string("dir1/file2.txt", "content2")
  s.set_string("dir2/subdir/file3.txt", "content3")
  s.set_string("root.txt", "root content")
  
  let count = count_files(s, "")
  inspect(count, content="4")
}

///|
test "count_files: directories themselves are not counted" {
  let s = test_storage()
  s.set_string("dir1/file1.txt", "content1")
  s.set_string("dir1/subdir/file2.txt", "content2")
  s.set_string("dir2/file3.txt", "content3")
  
  // Count should be 3 files, not including the directories dir1, dir1/subdir, dir2
  let count = count_files(s, "")
  inspect(count, content="3")
}

///|
test "count_files: count within specific prefix" {
  let s = test_storage()
  s.set_string("project1/src/main.txt", "main")
  s.set_string("project1/src/utils.txt", "utils")
  s.set_string("project1/docs/readme.txt", "readme")
  s.set_string("project2/file.txt", "other")
  
  // Count only files in project1
  let count = count_files(s, "project1")
  inspect(count, content="3")
  
  // Count only files in project1/src
  let src_count = count_files(s, "project1/src")
  inspect(src_count, content="2")
}

///|
test "count_files: nested directories with mixed content" {
  let s = test_storage()
  s.set_string("a/b/c/file1.txt", "1")
  s.set_string("a/b/file2.txt", "2")
  s.set_string("a/file3.txt", "3")
  s.set_string("x/y/file4.txt", "4")
  s.set_string("root.txt", "5")
  
  let total_count = count_files(s, "")
  inspect(total_count, content="5")
  
  let a_count = count_files(s, "a")
  inspect(a_count, content="3")
  
  let ab_count = count_files(s, "a/b")
  inspect(ab_count, content="2")
  
  let abc_count = count_files(s, "a/b/c")
  inspect(abc_count, content="1")
}