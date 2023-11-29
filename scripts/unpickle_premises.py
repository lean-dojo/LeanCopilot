import pickle
import torch
import numpy as np
import json


with open("indexed_corpus.pickle", "rb") as file:
    indexed_corpus = pickle.load(file)


embeddings_tensor = indexed_corpus.embeddings
embeddings_array = embeddings_tensor.numpy()
embeddings_array_64 = embeddings_array.astype(np.float64)

np.save("embeddings.npy", embeddings_array_64)
print("Embeddings saved to embeddings.npy")


all_premises = indexed_corpus.corpus.all_premises
premise_dict = {index: premise.full_name for index, premise in enumerate(all_premises)}

file_name = "dictionary.json"
with open(file_name, 'w') as file:
    json.dump(premise_dict, file, indent=4)
print(f"Dictionary saved to dictionary.json")
