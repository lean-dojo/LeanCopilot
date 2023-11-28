import LeanInfer

open LeanInfer
-- open Lean System

/-
#eval getConfig

def cfg : Config := {
  backend := .native $ .ct2 {
    generatorUrl := some ⟨"kaiyuy", "ct2-leandojo-lean4-tacgen-byt5-small"⟩,
    encoderUrl := some ⟨"kaiyuy", "ct2-leandojo-lean4-retriever-byt5-small"⟩
  },
  decoding := {numReturnSequences := 64}
}

#eval setConfig cfg
-/

-- def testtest : IO FilePath := do
def testEmbInit : IO Bool := do
--   -- LeanInfer.Cache.getRetrieverDir
  let uuu : Bool <- LeanInfer.initPremiseEmb
  println! uuu
  return LeanInfer.FFI.isPremiseEmbeddingsInitialized ()

#eval testEmbInit

def testDictInit : IO Bool := do
  let vvv : Bool <- LeanInfer.initPremiseDict
  println! vvv
  return LeanInfer.FFI.isPremiseDictionaryInitialized ()

#eval testDictInit

-- /-
example (n : Nat) : Nat.gcd n n = n := by
  select_premises
  sorry
-- -/

example (a b c : Nat) : a + b + c = a + c + b := by
  select_premises
  sorry

-- set_option LeanInfer.verbose false
-- set_option LeanInfer.suggest_tactics.check true

example (a b c : Nat) : a + b + c = a + c + b := by
  suggest_tactics
  sorry


example (a b c : Nat) : a + b + c = a + c + b := by
  suggest_tactics "rw"  -- You may provide a prefix to constrain the generated tactics.
  sorry
