import json
import pickle
import numpy as np


# indexed_corpurs.pickle is produced by retrieval/index.py in [ReProver](https://github.com/lean-dojo/ReProver).
indexed_corpus = pickle.load(open("indexed_corpus.pickle", "rb"))

embeddings_tensor = indexed_corpus.embeddings
embeddings_array = embeddings_tensor.numpy()
embeddings_array_64 = embeddings_array.astype(np.float64)

np.save("embeddings.npy", embeddings_array_64)
print("Embeddings saved to embeddings.npy")

all_premises = indexed_corpus.corpus.all_premises

premise_dict = {
    index: {"full_name": premise.full_name, "path": premise.path, "code": premise.code}
    for index, premise in enumerate(all_premises)
}

file_name = "dictionary.json"
json.dump(premise_dict, open(file_name, "wt"), indent=4)
print(f"Dictionary saved to dictionary.json")
