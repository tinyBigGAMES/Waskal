(module
  (memory $mem i64 1)
  (export "memory" (memory $mem))

  (func $mathlib.Add__int64_int64 (param $a i64) (param $b i64) (result i64)
    (local $_ret i64)
    (block $_exit
    (local.set $_ret (i64.add (local.get $a) (local.get $b)))
    br $_exit
    )
    (local.get $_ret)
  )

  (func $mathlib.Mul__int64_int64 (param $a i64) (param $b i64) (result i64)
    (local $_ret i64)
    (block $_exit
    (local.set $_ret (i64.mul (local.get $a) (local.get $b)))
    br $_exit
    )
    (local.get $_ret)
  )

  (export "Add" (func $mathlib.Add__int64_int64))

)
