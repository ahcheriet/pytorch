#ifndef THC_GENERIC_FILE
#define THC_GENERIC_FILE "THCUNN/generic/SpatialUpSamplingBicubic.cu"
#else

#include <THCUNN/upsampling.h>
#include <ATen/cuda/CUDAContext.h>

static inline void THNN_(SpatialUpSamplingBicubic_shapeCheck)
                        (THCState *state,
                         THCTensor *input, THCTensor *gradOutput,
                         int nBatch, int nChannels,
                         int inputHeight, int inputWidth,
                         int outputHeight, int outputWidth) {
  THArgCheck(inputHeight > 0 && inputWidth > 0
             && outputHeight > 0 && outputWidth > 0, 2,
             "input and output sizes should be greater than 0,"
             " but got input (H: %d, W: %d) output (H: %d, W: %d)",
             inputHeight, inputWidth, outputHeight, outputWidth);
  if (input != NULL) {
     THCUNN_argCheck(state, !input->is_empty() && input->dim() == 4, 2, input,
                     "non-empty 4D input tensor expected but got: %s");
  }

  if (gradOutput != NULL) {
    THCUNN_check_dim_size(state, gradOutput, 4, 0, nBatch);
    THCUNN_check_dim_size(state, gradOutput, 4, 1, nChannels);
    THCUNN_check_dim_size(state, gradOutput, 4, 2, outputHeight);
    THCUNN_check_dim_size(state, gradOutput, 4, 3, outputWidth);
  }
}

void THNN_(SpatialUpSamplingBicubic_updateOutput)(
           THCState *state,
           THCTensor *input,
           THCTensor *output,
           int outputHeight,
           int outputWidth,
           bool align_corners)
{
  int nbatch = THCTensor_(size)(state, input, 0);
  int channels = THCTensor_(size)(state, input, 1);
  int inputHeight = THCTensor_(size)(state, input, 2);
  int inputWidth = THCTensor_(size)(state, input, 3);
  THNN_(SpatialUpSamplingBicubic_shapeCheck)
       (state, input, NULL,
        nbatch, channels,
        inputHeight, inputWidth,
        outputHeight, outputWidth);

  THCUNN_assertSameGPU(state, 2, input, output);
  THCTensor_(resize4d)(state, output,
                       THCTensor_(size)(state, input, 0),
                       THCTensor_(size)(state, input, 1),
                       outputHeight, outputWidth);
  THCTensor_(zero)(state, output);
  THCDeviceTensor<scalar_t, 4> idata = toDeviceTensor<scalar_t, 4>(state, input);
  THCDeviceTensor<scalar_t, 4> odata = toDeviceTensor<scalar_t, 4>(state, output);
  THAssert(inputHeight > 0 && inputWidth > 0 && outputHeight > 0 && outputWidth > 0);

  // Get scaling factors
  const accreal rheight = linear_upsampling_compute_scale<accreal>(inputHeight, outputHeight, align_corners);
  const accreal rwidth = linear_upsampling_compute_scale<accreal>(inputWidth, outputWidth, align_corners);

  const int num_output_elements = outputHeight * outputWidth;
  const int max_threads =
    at::cuda::getCurrentDeviceProperties()->maxThreadsPerBlock;

  // Launch kernel
  cudaStream_t stream = THCState_getCurrentStream(state);
  bicubic_interp2d_kernel<scalar_t, accreal> <<<
    THCCeilDiv(num_output_elements, max_threads),
    max_threads,
    0,
    stream
  >>>(num_output_elements, rheight, rwidth, idata, odata);
  THCudaCheck(cudaGetLastError());
}


void THNN_(SpatialUpSamplingBicubic_updateGradInput)(
           THCState *state,
           THCTensor *gradOutput,
           THCTensor *gradInput,
           int nbatch,
           int nchannels,
           int inputHeight,
           int inputWidth,
           int outputHeight,
           int outputWidth,
           bool align_corners)
{
  THNN_(SpatialUpSamplingBicubic_shapeCheck)
       (state, NULL, gradOutput,
        nbatch, nchannels,
        inputHeight, inputWidth,
        outputHeight, outputWidth);
  gradOutput = THCTensor_(newContiguous)(state, gradOutput);
  THCUNN_assertSameGPU(state, 2, gradOutput, gradInput);
  THCTensor_(resize4d)(state, gradInput, nbatch, nchannels, inputHeight, inputWidth);
  THCTensor_(zero)(state, gradInput);
  THCDeviceTensor<scalar_t, 4> in_data = toDeviceTensor<scalar_t, 4>(state, gradInput);
  THCDeviceTensor<scalar_t, 4> out_data = toDeviceTensor<scalar_t, 4>(state, gradOutput);
  const accreal rheight = linear_upsampling_compute_scale<accreal>(inputHeight, outputHeight, align_corners);
  const accreal rwidth = linear_upsampling_compute_scale<accreal>(inputWidth, outputWidth, align_corners);
  const int num_kernels = outputHeight * outputWidth;
  const int num_threads =
    at::cuda::getCurrentDeviceProperties()->maxThreadsPerBlock;
  cudaStream_t stream = THCState_getCurrentStream(state);
  bicubic_interp2d_backward_kernel<scalar_t ,accreal> <<<THCCeilDiv(num_kernels, num_threads),
  num_threads, 0, stream>>>(num_kernels, rheight, rwidth, align_corners, in_data, out_data);
  THCudaCheck(cudaGetLastError());
  THCTensor_(free)(state, gradOutput);
}

#endif
