/// libvpx-style helpers. Only [memset] is currently used; legacy `memset32`,
/// `memcpy` and `copyEntropyValues` were unused and depended on `dynamic`
/// shapes that no longer exist on the typed `FRAME_CONTEXT` struct.
void memset(List<int> ptr, int ptrOff, int value, int num) {
  var i = num;
  while (i-- > 0) {
    ptr[ptrOff + i] = value;
  }
}
