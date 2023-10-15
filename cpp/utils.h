#include <string>
#include <fstream>

inline bool exists(const std::string &path) {
  std::ifstream f(path.c_str());
  return f.good();
}

static lean_obj_res lean_mk_pair(lean_obj_arg a, lean_obj_arg b) {
  lean_object *r = lean_alloc_ctor(0, 2, 0);
  lean_ctor_set(r, 0, a);
  lean_ctor_set(r, 1, b);
  return r;
}
