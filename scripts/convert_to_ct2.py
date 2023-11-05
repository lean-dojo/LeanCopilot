import numpy as np
from transformers import AutoTokenizer
import ctranslate2
from ctranslate2.converters.transformers import (
    TransformersConverter,
    ModelLoader,
    _MODEL_LOADERS,
    _SUPPORTED_ACTIVATIONS,
)
from ctranslate2.specs import transformer_spec, common_spec
import ctranslate2.converters.utils as utils


class T5EncoderLoader(ModelLoader):
    @property
    def architecture_name(self):
        return "T5EncoderModel"

    def get_model_spec(self, model):
        encoder_spec = transformer_spec.TransformerEncoderSpec(
            model.config.num_layers,
            model.config.num_heads,
            pre_norm=True,
            activation=_SUPPORTED_ACTIVATIONS[model.config.dense_act_fn],
            ffn_glu=model.config.is_gated_act,
            relative_attention_bias=True,
            rms_norm=True,
        )
        spec = transformer_spec.TransformerEncoderModelSpec(encoder_spec)
        self.set_stack(spec.encoder, model.encoder)
        return spec

    def get_vocabulary(self, model, tokenizer):
        tokens = super().get_vocabulary(model, tokenizer)

        extra_ids = model.config.vocab_size - len(tokens)
        for i in range(extra_ids):
            tokens.append("<extra_id_%d>" % i)

        return tokens

    def set_vocabulary(self, spec, tokens):
        spec.register_vocabulary(tokens)

    def set_config(self, config, model, tokenizer):
        config.bos_token = tokenizer.pad_token
        config.eos_token = tokenizer.eos_token
        config.unk_token = tokenizer.unk_token

    def set_stack(self, spec, module):
        self.set_layer_norm(spec.layer_norm, module.final_layer_norm)
        self.set_embeddings(
            spec.embeddings[0]
            if isinstance(spec.embeddings, list)
            else spec.embeddings,
            module.embed_tokens,
        )

        spec.scale_embeddings = False

        for i, (layer_spec, block) in enumerate(zip(spec.layer, module.block)):
            self.set_self_attention(layer_spec.self_attention, block.layer[0])

            if i > 0:
                # Reuse relative attention bias from the first layer.
                first_self_attention = spec.layer[0].self_attention
                layer_spec.self_attention.relative_attention_bias = (
                    first_self_attention.relative_attention_bias
                )
                layer_spec.self_attention.relative_attention_max_distance = (
                    first_self_attention.relative_attention_max_distance
                )

            self.set_ffn(layer_spec.ffn, block.layer[-1])

    def set_ffn(self, spec, module):
        if hasattr(spec, "linear_0_noact"):
            self.set_linear(spec.linear_0, module.DenseReluDense.wi_0)
            self.set_linear(spec.linear_0_noact, module.DenseReluDense.wi_1)
        else:
            self.set_linear(spec.linear_0, module.DenseReluDense.wi)

        self.set_linear(spec.linear_1, module.DenseReluDense.wo)
        self.set_layer_norm(spec.layer_norm, module.layer_norm)

    def set_self_attention(self, spec, module):
        self.set_attention(spec, module.SelfAttention, self_attention=True)
        self.set_layer_norm(spec.layer_norm, module.layer_norm)

    def set_attention(self, spec, attention, self_attention=False):
        spec.queries_scale = 1.0

        split_layers = [common_spec.LinearSpec() for _ in range(3)]
        self.set_linear(split_layers[0], attention.q)
        self.set_linear(split_layers[1], attention.k)
        self.set_linear(split_layers[2], attention.v)

        if self_attention:
            utils.fuse_linear(spec.linear[0], split_layers)
        else:
            utils.fuse_linear(spec.linear[0], split_layers[:1])
            utils.fuse_linear(spec.linear[1], split_layers[1:])

        self.set_linear(spec.linear[-1], attention.o)

        if attention.has_relative_attention_bias:
            spec.relative_attention_bias = attention.relative_attention_bias.weight
            spec.relative_attention_max_distance = np.dtype("int32").type(
                attention.relative_attention_max_distance
            )

    def set_layer_norm(self, spec, layer_norm):
        spec.gamma = layer_norm.weight


_MODEL_LOADERS["T5Config"] = T5EncoderLoader()

converter = TransformersConverter("kaiyuy/leandojo-lean4-retriever-byt5-small")
converter.convert("ct2-leandojo-lean4-retriever-byt5-small", force=True)

encoder = ctranslate2.Encoder("ct2-leandojo-lean4-retriever-byt5-small")
state = "n : ℕ\n⊢ gcd n n = n"
tokenizer = AutoTokenizer.from_pretrained("kaiyuy/leandojo-lean4-retriever-byt5-small")
output = encoder.forward_batch(
    [tokenizer.convert_ids_to_tokens(tokenizer.encode(state))]
)
feature = np.array(output).mean(axis=1)
