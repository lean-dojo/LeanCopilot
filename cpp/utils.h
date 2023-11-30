#include <string>
#include <fstream>

inline bool exists(const std::string &path) {
  std::ifstream f(path.c_str());
  return f.good();
}

inline lean_obj_res lean_mk_pair(lean_obj_arg a, lean_obj_arg b) {
  lean_object *r = lean_alloc_ctor(0, 2, 0);
  lean_ctor_set(r, 0, a);
  lean_ctor_set(r, 1, b);
  return r;
}

inline lean_obj_res lean_mk_4_tuples(lean_obj_arg a, lean_obj_arg b, lean_obj_arg c, lean_obj_arg d) {
  lean_object *r = lean_alloc_ctor(0, 4, 0);
  lean_ctor_set(r, 0, a);
  lean_ctor_set(r, 1, b);
  lean_ctor_set(r, 2, c);
  lean_ctor_set(r, 3, d);
  return r;
}