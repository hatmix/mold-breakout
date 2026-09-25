@tool
extends RefCounted
## Edge adjacency is built once; silhouette classification happens per camera on the GPU.
static func build(faces: PackedVector3Array, segments:=PackedVector3Array()) -> ArrayMesh:
 var edges: Dictionary={}
 for i in range(0,faces.size(),3):
  var normal: Vector3=(faces[i+1]-faces[i]).cross(faces[i+2]-faces[i]).normalized()
  if normal.is_zero_approx():continue
  for j in 3:
   var a:=faces[i+j];var b:=faces[i+(j+1)%3]
   var ka:=a.snapped(Vector3.ONE*0.00001);var kb:=b.snapped(Vector3.ONE*0.00001)
   var key: Array=[ka,kb] if ka<kb else [kb,ka]
   if edges.has(key):edges[key].append(normal)
   else:edges[key]=[a,b,normal]
 for i in range(0,segments.size(),2):edges[[i]]=[segments[i],segments[i+1],Vector3.ZERO]
 var vertices:=PackedVector3Array();var normals:=PackedVector3Array();var uvs:=PackedVector2Array()
 var other:=PackedFloat32Array();var adjacent:=PackedFloat32Array()
 for edge in edges.values():
  var boundary: bool=edge.size()==3
  # Coplanar interior edges never contribute to a silhouette.
  if not boundary and absf(edge[2].dot(edge[3]))>0.99999:continue
  for corner in [[0,-1],[1,1],[1,-1],[0,-1],[1,-1],[0,1]]:
   var index: int=corner[0]
   vertices.append(edge[index]);normals.append(edge[2]);uvs.append(Vector2(corner[1],index))
   var opposite: Vector3=edge[1-index]
   other.append_array(PackedFloat32Array([opposite.x,opposite.y,opposite.z,0]))
   var n: Vector3=Vector3.ZERO if boundary else edge[3]
   adjacent.append_array(PackedFloat32Array([n.x,n.y,n.z,1 if boundary else 0]))
 var mesh:=ArrayMesh.new()
 if vertices.is_empty():return mesh
 var arrays: Array=[];arrays.resize(Mesh.ARRAY_MAX)
 arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals;arrays[Mesh.ARRAY_TEX_UV]=uvs
 arrays[Mesh.ARRAY_CUSTOM0]=other;arrays[Mesh.ARRAY_CUSTOM1]=adjacent
 mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},(Mesh.ARRAY_CUSTOM_RGBA_FLOAT<<Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)|(Mesh.ARRAY_CUSTOM_RGBA_FLOAT<<Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT))
 return mesh
