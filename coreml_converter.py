import coremltools

coreml_model = coremltools.converters.keras.convert('mnist.h5', input_names='image', image_input_names='image')
coreml_model.save('mnist.mlmodel')
