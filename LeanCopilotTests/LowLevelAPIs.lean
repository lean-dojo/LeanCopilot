import LeanCopilot

open LeanCopilot

def url := Url.parse! "https://huggingface.co/kaiyuy/ct2-leandojo-lean4-tacgen-byt5-small"

#eval generate model "a b : ℕ\n⊢ a + b = b + a"
