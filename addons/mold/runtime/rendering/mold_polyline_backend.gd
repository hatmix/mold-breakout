class_name MoldPolylineBackend
extends RefCounted

## Runtime backend policy used by MoldPolylineNode3D.
enum Mode {
	## Use the GPU backend when it is available, otherwise CPU.
	AUTO = 0,
	## Always use MoldWorld's cached CPU-generated mesh backend.
	CPU = 1,
}
