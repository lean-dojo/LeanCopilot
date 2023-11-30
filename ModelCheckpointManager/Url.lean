import Lean

open System (FilePath)

set_option autoImplicit false

namespace LeanCopilot


structure Url where
  protocol : String
  hostname : String
  path : FilePath
deriving Inhabited, Repr


namespace Url


def isValid (url : Url) : Bool :=
  ¬ url.protocol.isEmpty ∧ ¬ url.hostname.isEmpty ∧ ¬ url.path.toString.isEmpty ∧ url.path.isRelative


def toString (url : Url) : String :=
  assert! isValid url
  s!"{url.protocol}://{url.hostname}/{url.path}"


instance : ToString Url := ⟨toString⟩


def parse (s : String) : Option Url :=
  let parts := s.splitOn "://"
  if h : parts.length != 2 then
    none
  else
    have : parts.length > 1 := by
      by_cases h' : parts.length = 2
      · rw [h']
        apply Nat.lt_succ_of_le
        simp
      · simp_all
    have : parts.length > 0 := by
      apply Nat.lt_of_succ_lt
      assumption
    let protocol := parts[0]
    match parts[1].splitOn "/" with
    | hostname :: path =>
      let path := FilePath.mk $ "/".intercalate path
      let url : Url := ⟨protocol, hostname, path⟩
      if url.isValid then
        some url
      else
        none
    | _ => none


def parse! (s : String) : Url :=
  match parse s with
  | some url => url
  | none => panic! "Invalid url: {s}"


#eval parse! "https://huggingface.co/kaiyuy/ct2-leandojo-lean4-tacgen-byt5-small"
#eval parse! "https://huggingface.co/bert-base-uncased"


end Url

end LeanCopilot
