
## Build CTranslate2 from Source

Add `set(CMAKE_C_COMPILER "clang")` and `set(CMAKE_CXX_COMPILER "clang++")` to CMakeLists.txt

```bash
cmake -DCMAKE_INSTALL_PREFIX=/home/kaiyu/local/usr -DOPENMP_RUNTIME=COMP -DWITH_CUDA=ON -DWITH_CUDNN=ON ..
make -j16
make install
```


## Build LeanInfer

Maybe need to `--load-dynlib=/opt/intel/oneapi/dnnl/latest/cpu_gomp/lib/libdnnl.so` to `weakLeanArgs` (maybe not for Mac)