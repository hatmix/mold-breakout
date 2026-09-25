#ifndef MOLD_BILLBOARD_STROKE
#define MOLD_BILLBOARD_STROKE
// Both CPU mesh attributes and GPU point streams use this analytic ribbon layout.
vec2 mold_gpu_dir(vec2 delta, vec2 fallback) {
    float size = length(delta);
    return size > 0.00001 ? delta / size : fallback;
}
vec2 mold_gpu_normal(vec2 direction) { return vec2(-direction.y, direction.x); }
float mold_gpu_cross(vec2 a, vec2 b) { return a.x*b.y-a.y*b.x; }
vec2 mold_gpu_outline(vec2 incoming, vec2 outgoing, vec2 normal, float side,
        float radius, float neighbor, bool endpoint, int mold_gpu_join, float mold_gpu_miter_limit) {
    if (endpoint || (mold_gpu_join != 0 && mold_gpu_cross(incoming,outgoing)*side < 0.0))
        return normal * side * radius;
    vec2 sum = mold_gpu_normal(incoming) + mold_gpu_normal(outgoing);
    float denominator = dot(sum, mold_gpu_normal(outgoing));
    if (abs(denominator) < 0.00001) return normal * side * radius;
    vec2 offset = sum * (side * radius / denominator);
    float limit = min(radius * mold_gpu_miter_limit, neighbor * 0.5 + radius);
    return length(offset) > limit ? normalize(offset)*limit : offset;
}
void mold_stroke_vertex(vec4 previous, vec4 a, vec4 b, vec4 next, vec4 metrics,
        int local_id, int mold_gpu_join, int mold_gpu_cap, float mold_gpu_miter_limit,
        out vec3 position, out vec2 uv, out vec4 custom0, out vec4 custom1, out vec4 custom2) {
    int flags = int(round(metrics.x));
    bool first = (flags & 1) != 0;
    bool last = (flags & 2) != 0;
    vec2 direction = mold_gpu_dir(b.xy-a.xy, vec2(1.0,0.0));
    vec2 incoming = first ? direction : mold_gpu_dir(a.xy-previous.xy,direction);
    vec2 outgoing = last ? direction : mold_gpu_dir(next.xy-b.xy,direction);
    vec2 normal = mold_gpu_normal(direction);
    float segment_length = length(b.xy-a.xy);
    float progress = metrics.y / max(metrics.w,0.00001);
    position = a.xyz;
    uv = vec2(progress,0.5);
    custom0 = vec4(0.0,0.0,0.0,max(a.w*0.5,0.00001));
    custom1 = vec4(0.0); custom2 = vec4(0.0);
    int corners[6] = int[6](0,1,2,0,2,3);
    if (local_id < 12) {
        float side = local_id < 6 ? 1.0 : -1.0;
        int corner_id = local_id % 6;
        if (side < 0.0) { if (corner_id % 3 == 1) corner_id += 1; else if (corner_id % 3 == 2) corner_id -= 1; }
        int corner = corners[corner_id];
        bool at_start = corner < 2;
        bool outline = corner == 1 || corner == 2;
        vec4 current = at_start ? a : b;
        float radius = max(current.w*0.5,0.00001);
        vec2 offset = vec2(0.0);
        if (outline) offset = at_start
            ? mold_gpu_outline(incoming,direction,normal,side,radius,min(length(a.xy-previous.xy),segment_length),first,mold_gpu_join,mold_gpu_miter_limit)
            : mold_gpu_outline(direction,outgoing,normal,side,radius,min(length(next.xy-b.xy),segment_length),last,mold_gpu_join,mold_gpu_miter_limit);
        vec2 start_shift = first && mold_gpu_cap == 1 ? -direction*a.w*0.5 : vec2(0.0);
        vec2 end_shift = last && mold_gpu_cap == 1 ? direction*b.w*0.5 : vec2(0.0);
        vec2 shift = at_start ? start_shift : end_shift;
        float line_length = segment_length + length(start_shift)+length(end_shift);
        bool start_cap = first && mold_gpu_cap != 2;
        bool end_cap = last && mold_gpu_cap != 2;
        vec2 extrusion = offset;
        if (at_start && start_cap) extrusion -= direction*radius;
        if (!at_start && end_cap) extrusion += direction*radius;
        float x = (at_start ? 0.0 : line_length)+dot(offset,direction);
        float y = dot(offset,normal)/radius;
        custom0 = vec4(extrusion,0.0,radius);
        custom1 = vec4(normal.x,y,start_cap ? 1.0-x/radius : 0.0,end_cap ? 1.0-(line_length-x)/radius : 0.0);
        custom2 = vec4(normal.y,dot(extrusion,normal)/radius,start_cap ? -dot(extrusion,direction)/radius : 0.0,end_cap ? dot(extrusion,direction)/radius : 0.0);
        position = current.xyz+vec3(offset+shift,0.0);
        progress = clamp((at_start ? metrics.y : metrics.z)+dot(offset,direction),metrics.y,metrics.z)/max(metrics.w,0.00001);
        uv = vec2(progress,0.5-y*0.5);
    } else {
        bool at_start = local_id < 24;
        int decoration_id = (local_id-12) % 12;
        vec4 current = at_start ? a : b;
        position = current.xyz;
        float radius = max(current.w*0.5,0.00001);
        bool endpoint = at_start ? first : last;
        bool active = endpoint ? mold_gpu_cap == 2 : at_start && mold_gpu_join != 0;
        float turn = mold_gpu_cross(incoming,direction);
        float side = turn > 0.0 ? -1.0 : 1.0;
        vec2 from = endpoint ? (at_start ? normal : -normal) : mold_gpu_normal(incoming)*side;
        vec2 to = endpoint ? -from : normal*side;
        vec2 offset = vec2(0.0);
        bool round_join = endpoint || mold_gpu_join == 2;
        if (active && (endpoint || abs(turn)>0.00001)) {
            if (round_join) {
                float start_angle = atan(from.y,from.x);
                float delta = endpoint ? 3.14159265359 : atan(mold_gpu_cross(from,to),dot(from,to));
                int steps = abs(delta) > 1.57080632679 ? 2 : 1;
                int step_id = decoration_id/6;
                if (step_id < steps) {
                    float angle_a = start_angle+delta*float(step_id)/float(steps);
                    float angle_b = start_angle+delta*float(step_id+1)/float(steps);
                    int corner_id = decoration_id%6;
                    if (delta > 0.0) { if (corner_id%3==1) corner_id+=1; else if (corner_id%3==2) corner_id-=1; }
                    int corner = corners[corner_id];
                    if (corner==1) offset=vec2(cos(angle_a),sin(angle_a));
                    if (corner==2) offset=vec2(cos((angle_a+angle_b)*0.5),sin((angle_a+angle_b)*0.5))/cos((angle_b-angle_a)*0.5);
                    if (corner==3) offset=vec2(cos(angle_b),sin(angle_b));
                }
                custom1=vec4(offset,0.0,0.0); custom2=custom1;
            } else {
                int corner=decoration_id;
                if (turn > 0.0) { if(corner==1) corner=2; else if(corner==2) corner=1; }
                if(corner==1) offset=from; else if(corner==2) offset=to;
                vec2 axis=mold_gpu_dir(from+to,normal);
                vec2 bevel_axis=axis/max(dot(axis,from),0.00001);
                custom1=vec4(0.0,dot(offset,bevel_axis),0.0,0.0); custom2=custom1;
            }
        }
        custom0=vec4(offset*radius,round_join ? 2.0 : 1.0,radius);
        position+=vec3(offset*radius,0.0);
        progress=(at_start ? metrics.y : metrics.z)/max(metrics.w,0.00001);
        uv=vec2(progress,0.5-(length(offset)>0.00001 ? dot(normalize(offset),normal)*0.5 : 0.0));
    }
}
float mold_stroke_near(mat4 projection) {
    mat4 inv = inverse(projection);
    vec4 a = inv*vec4(0.0,0.0,1.0,1.0);
    vec4 b = inv*vec4(0.0,0.0,-1.0,1.0);
    return min(abs(a.z/a.w),abs(b.z/b.w));
}
bool mold_stroke_start(int id) {
    int corner[6] = int[6](0,1,2,0,2,3);
    int index = id % 6;
    if (id >= 6 && id < 12) { if (index % 3 == 1) index += 1; else if (index % 3 == 2) index -= 1; }
    return id < 12 ? corner[index] < 2 : id < 24;
}
// Project neighbours onto the camera plane through this vertex's centerline.
// Each endpoint retains its own depth and physical width under perspective.
void mold_billboard_vertex(vec4 previous, vec4 a, vec4 b, vec4 next, vec4 metrics,
        int id, int join_mode, int cap_mode, float miter_limit, mat4 model_view,
        float width_scale, bool perspective, float near_plane,
        out vec3 position, out vec2 uv, out vec4 c0, out vec4 c1, out vec4 c2) {
    previous.xyz = (model_view * vec4(previous.xyz,1.0)).xyz;
    a.xyz = (model_view * vec4(a.xyz,1.0)).xyz;
    b.xyz = (model_view * vec4(b.xyz,1.0)).xyz;
    next.xyz = (model_view * vec4(next.xyz,1.0)).xyz;
    // Clip the centerline before dividing by depth. Hardware clips the ribbon.
    float clip_z = -max(near_plane,0.0001);
    bool hidden = a.z > clip_z && b.z > clip_z;
    if (!hidden) {
        if (a.z > clip_z) { a = mix(a,b,(clip_z-a.z)/(b.z-a.z)); previous = a; metrics.x = float(int(metrics.x)|1); }
        if (b.z > clip_z) { b = mix(b,a,(clip_z-b.z)/(a.z-b.z)); next = b; metrics.x = float(int(metrics.x)|2); }
    }
    vec3 center = mold_stroke_start(id) ? a.xyz : b.xyz;
    float depth = max(-center.z, max(near_plane,0.0001));
    if (perspective) {
        previous.xy *= depth/max(-previous.z,max(near_plane,0.0001));
        a.xy *= depth/max(-a.z,max(near_plane,0.0001));
        b.xy *= depth/max(-b.z,max(near_plane,0.0001));
        next.xy *= depth/max(-next.z,max(near_plane,0.0001));
        a.w *= depth/max(-a.z,max(near_plane,0.0001));
        b.w *= depth/max(-b.z,max(near_plane,0.0001));
    }
    a.w *= width_scale; b.w *= width_scale;
    vec2 projected_center = mold_stroke_start(id) ? a.xy : b.xy;
    mold_stroke_vertex(previous,a,b,next,metrics,id,join_mode,cap_mode,miter_limit,position,uv,c0,c1,c2);
    position = center + vec3(position.xy-projected_center,0.0);
    if (hidden) { position = vec3(0.0,0.0,1.0); c0 = vec4(0.0); }
}
#endif
