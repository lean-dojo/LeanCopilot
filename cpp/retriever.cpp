#include <lean/lean.h>


extern "C" lean_obj_res encode(b_lean_obj_arg input) {
  lean_object *arr = lean_mk_empty_float_array(lean_box(10));
  // Not implemented yet.
  lean_float_array_push(arr, 0.34);
  lean_float_array_push(arr, 0.84);
  lean_float_array_push(arr, 0.57);
  lean_float_array_push(arr, 2.63);
  lean_float_array_push(arr, 0.67);
  return arr;
}
