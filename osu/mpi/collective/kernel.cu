__global__ 
void compute_kernel(float a, float * x, float * y, int N) 
{
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    
    int count = 0;
    
    if (i < N) {
        for(count=0; count < (N/8); count++) { 
            y[i] = a * x[i] + y[i];
        }
    }
}   

extern "C" 
void 
call_kernel(float a, float * d_x, float * d_y, int N, cudaStream_t * stream)
{
    compute_kernel<<<(N+255)/256, 256, 0, *stream>>>(a, d_x, d_y, N);
}


