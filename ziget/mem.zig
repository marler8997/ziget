pub fn cmp(comptime T: type, a: [*]const T, b: [*]const T, len: usize) bool {
    var i : usize = 0;
    while (i < len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}
