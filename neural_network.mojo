from python import Python
from tensor import Tensor, TensorSpec, TensorShape
from collections.vector import InlinedFixedVector

@value
struct NeuralNetwork[dtype: DType](Hashable):
    var spec: List[Int]
    var data: AnyPointer[PythonObject]
    var hash: Int
    var data_spec: List[TensorSpec]
    
    fn __init__(inout self, spec: List[Int]) raises:
        var torch = Python.import_module("torch")
        self.spec = spec
        self.data = AnyPointer[PythonObject].alloc((len(spec) - 1) * 2)
        self.hash = int(self.data)
        self.data_spec = List[TensorSpec]()
        for i in range(0, len(spec) - 1):
            self.data[2*i] = torch.rand(spec[i+1], spec[i])
            self.data[2*i+1] = torch.rand(spec[i+1], 1)
            self.data_spec.append(TensorSpec(dtype, spec[i+1], spec[i]))
            self.data_spec.append(TensorSpec(dtype, spec[i+1], 1))

    fn __init__(inout self, spec: List[Int], owned data: AnyPointer[PythonObject], owned data_spec: List[TensorSpec]):
        self.spec = spec
        self.data = data
        self.hash = int(self.data)
        self.data_spec = data_spec

    fn __moveinit__(inout self, owned existing: Self):
        self = Self(existing.spec, existing.data, existing.data_spec)

    fn __hash__(self) -> Int:
        return self.hash

    fn __str__(self) -> String:
        var result: String = "NeuralNetwork(\n"
        for i in range(len(self.data_spec)):
            var tensor = Tensor[dtype]()
            try:
                tensor = self._export_tensor(i)
            except:
                pass
            result += str(tensor)
        result += ")"
        return result

    fn __repr__(self) -> String:
        var result: String = "NeuralNetwork-"
        for i in self.spec:
            result += str(i[])

        return result

    fn __del__(owned self):
        self.data.free()

    fn __getitem__(self, index: Int) raises -> PythonObject:
        if index >= len(self.data_spec) or index < 0:
            raise Error("Data index out of range")

        return self.data[index]

    fn __getitem__(self, idx: Int, idx_row: Int) raises -> PythonObject:
        if idx_row >= self.data_spec[idx][0] or idx_row < 0:
            raise Error("Row index out of range")

        return self[idx][idx_row]

    fn __getitem__(self, idx: Int, idx_row: Int, idx_col: Int) raises -> SIMD[dtype, 1]:
        if idx_col >= self.data_spec[idx][1] or idx_col < 0:
            raise Error("Column index out of range")

        return SIMD[DType.float64, 1](self[idx, idx_row][idx_col].to_float64()).cast[dtype]()

    fn __setitem__(inout self, index: Int, value: PythonObject) raises:
        if index >= len(self.data_spec) or index < 0:
            raise Error("Index out of range")

        self.data[index] = value

    fn tensor_spec(self, index: Int) raises -> TensorSpec:
        if index >= len(self.data_spec) or index < 0:
            raise Error("Index out of range")

        return self.data_spec[index]

    fn feed(self, input_array: PythonObject) raises -> PythonObject:
        if len(input_array) != self.spec[0]:
            raise Error("Input tensor has wrong dimensions")

        var torch = Python.import_module("torch")
        var output_array = input_array
        for i in range(len(self.spec) - 1):
            output_array = torch.special.expit(torch.mm(self.data[2*i], output_array) + self.data[2*i+1])
        return output_array

    fn copy(inout self, existing: Self) raises:
        for i in range(len(self.data_spec)):
            if self.data_spec[i] != existing.data_spec[i]:
                raise("Doesn't match existing data specification")
            
        for i in range(len(self.data_spec)):
            self.data[i] = existing.data[i]

    fn mutate(inout self, strength: Float32) raises:
        var torch = Python.import_module("torch")
        for i in range(len(self.data_spec)):
            self[i] = self[i] + strength * torch.randn_like(self[i])

    fn average(inout self: Self, other: Self) raises:
        for i in range(len(self.data_spec)):
            self[i] = (self[i] + other.data[i]) * 0.5

    fn _export_tensor(self, index: Int) raises -> Tensor[dtype]:
        if index >= len(self.data_spec) or index < 0:
            raise Error("Index out of range")
        
        var pytorch_tensor = self.data[index]
        var mojo_tensor = Tensor[dtype](self.data_spec[index])
        for row in range(self.data_spec[index][0]):
            for column in range(self.data_spec[index][1]):
                var map_index = StaticIntTuple[2](row, column)
                var value: SIMD[dtype, 1] = self[index, row, column]
                mojo_tensor.__setitem__(map_index, value)

        return mojo_tensor

    @staticmethod
    fn _import_tensor(mojo_tensor: Tensor[dtype]) raises -> PythonObject:
        var torch = Python.import_module("torch")
        var tensor_rows = mojo_tensor.shape()[0]
        var tensor_cols = mojo_tensor.shape()[1]
        var pytorch_tensor = torch.zeros([tensor_rows, tensor_cols])
        for row in range(tensor_rows):
            for column in range(tensor_cols):
                var map_index = StaticIntTuple[2](row, column)
                var value = mojo_tensor.__getitem__(map_index)
                pytorch_tensor.__setitem__((row, column), value)
        
        return pytorch_tensor

    fn _dump_tensor(self, habitat_index: Int, layer_index: Int) raises:
        var filename = "data/" + str(self.__repr__()) + "-" + str(habitat_index) + "-" +str(layer_index)
        var current_layer = self._export_tensor(layer_index)
        current_layer.save(filename)

    fn save(inout self, habitat_index: Int) raises:
        for layer_index in range(len(self.data_spec)):
            self._dump_tensor(habitat_index, layer_index)

    fn _load_tensor(inout self, habitat_index: Int, layer_index: Int) raises:
        var torch = Python.import_module("torch")
        var filename = "data/" + str(self.__repr__()) + "-" + str(habitat_index) + "-" +str(layer_index)
        var mojo_tensor = Tensor[dtype].load(filename)
        var pytorch_tensor = NeuralNetwork._import_tensor(mojo_tensor)
        self[layer_index] = pytorch_tensor

    fn load(inout self, habitat_index: Int) raises:
        for layer_index in range(len(self.data_spec)):
            self._load_tensor(habitat_index, layer_index)