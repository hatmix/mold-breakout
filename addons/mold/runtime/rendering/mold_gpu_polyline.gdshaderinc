#include "mold_billboard_polyline.gdshaderinc"
uniform int mold_gpu_geometry = 0;
uniform vec4 mold_gpu_dash = vec4(0.0);
uniform int mold_gpu_dash_cap = -1;
// Further reading: Nicolas P. Rougier, "Shader-Based Antialiased, Dashed, Stroked
// Polylines", Journal of Computer Graphics Techniques 2(2), 2013, pp. 105-121.
// https://jcgt.org/published/0002/02/08/paper.pdf
// Covers analytic caps/joins and a dash atlas for arbitrary patterns. Mold currently
// clips dash intervals in the vertex stage; the paper is a reference for future work.
// Dash slots are clipped in path distance before stroke extrusion. No UV mask.
vec3 mold_dash_pattern(vec4 dash, float total, bool closed) {
    float gap = dash.x > 0.0 ? dash.y : dash.y / max(-dash.x + dash.y, 0.00001);
    float repeats = dash.x > 0.0 ? dash.x-gap : total/max(-dash.x+dash.y,0.00001);
    float phase = dash.w;
    if (dash.x < 0.0) {
        if (dash.z > 1.5) repeats=max(floor(repeats+gap+0.00001),1.0)-gap;
        else if (dash.z > 0.5) { repeats=max(1.0,floor(repeats+0.5)); phase-=gap*0.5; }
    }
    repeats=max(repeats,0.00001);
    if (closed && (dash.x > 0.0 || dash.z > 0.5)) {
        repeats=dash.x > 0.0 ? dash.x : max(1.0,floor(total/max(-dash.x+dash.y,0.00001)+0.5));
        phase=dash.w+(1.0-gap)*0.5;
    }
    return vec3(repeats,gap,phase-floor(phase));
}
bool mold_dash_segment(vec4 dash, int slot, vec4 neighbors,
        inout vec4 previous, inout vec4 a, inout vec4 b, inout vec4 next,
        inout vec4 metrics, out vec2 cuts) {
    cuts=vec2(0.0,1.0);
    vec3 pattern=mold_dash_pattern(dash,metrics.w,neighbors.z>0.5);
    if (pattern.y <= 0.0) return slot == 0;
    if (pattern.y >= 1.0 || pattern.x <= 0.0) return false;
    float period=metrics.w/pattern.x;
    float on=period*(1.0-pattern.y);
    float start=metrics.y, end=metrics.z;
    float run=(floor(start/period+pattern.z)+float(slot)-pattern.z)*period;
    float lo=max(start,run), hi=min(end,run+on);
    if (hi-lo <= metrics.w*0.0000001) return false;
    float before=lo-run, after=run+on-hi;
    // Closed seams can merge even when the unsnapped pattern does not tile.
    if (neighbors.z>0.5 && lo==0.0) {
        float p=metrics.w/period+pattern.z;
        float f=p-floor(p);
        before=(f>0.0 && f<=1.0-pattern.y) ? f*period : 0.0;
    }
    if (neighbors.z>0.5 && hi==metrics.w) {
        float f=pattern.z;
        after=f<1.0-pattern.y ? (1.0-pattern.y-f)*period : 0.0;
    }
    int flags=int(round(metrics.x));
    bool first=(flags & 1)!=0 || lo>start || before<=period*0.000001;
    bool last=(flags & 2)!=0 || hi<end || after<=period*0.000001;
    cuts=vec2((lo-start)/max(end-start,0.00000001),(hi-start)/max(end-start,0.00000001));
    vec4 original=a;
    a=mix(original,b,cuts.x); b=mix(original,b,cuts.y);
    previous=first ? a : mix(a,previous,min(1.0,before/max(neighbors.x,0.00000001)));
    next=last ? b : mix(b,next,min(1.0,after/max(neighbors.y,0.00000001)));
    metrics=vec4(float((first ? 1 : 0)+(last ? 2 : 0)),lo,hi,metrics.w);
    return true;
}

// GPU stream: two RGBA32F texels per point, three per segment.
// Third segment texel: previous/next metric length, closed, reserved.
// Segment: previous/start/end/next indices; flags/start-distance/end-distance/path-length.
uniform sampler2D mold_gpu_points : filter_nearest, repeat_disable;
uniform sampler2D mold_gpu_segments : filter_nearest, repeat_disable;
uniform int mold_gpu_vertices_per_segment = 12;
// Unbounded default preserves independently supplied streams. Prepared C# carriers set their active count.
uniform int mold_gpu_active_segments = 2147483647;
uniform int mold_gpu_join = 0;
uniform int mold_gpu_cap = 0;
uniform float mold_gpu_miter_limit = 4.0;
vec4 mold_gpu_fetch(sampler2D data, int index) {
    int width = textureSize(data, 0).x;
    return texelFetch(data, ivec2(index % width, index / width), 0);
}
// Produces the same analytic attributes consumed by the cached CPU stroke shader.
void mold_gpu_vertex(int vertex_id, out vec3 position, out vec4 color, out vec2 uv,
        out vec4 custom0, out vec4 custom1, out vec4 custom2, inout mat4 model_view, mat4 model, mat4 projection, out vec3 author_position) {
    int segment = vertex_id / mold_gpu_vertices_per_segment;
    int local_id = vertex_id % mold_gpu_vertices_per_segment;
    if (segment >= mold_gpu_active_segments || (mold_gpu_dash.x == 0.0 && local_id >= 36)) {
        position=vec3(0.0); color=vec4(0.0); uv=vec2(0.0); custom0=vec4(0.0); custom1=vec4(0.0); custom2=vec4(0.0); author_position=vec3(0.0);
        return;
    }
    ivec4 indices = ivec4(round(mold_gpu_fetch(mold_gpu_segments, segment*3)));
    vec4 metrics = mold_gpu_fetch(mold_gpu_segments, segment*3+1);
    int flags = int(round(metrics.x));
    bool first = (flags & 1) != 0;
    bool last = (flags & 2) != 0;
    vec4 previous = mold_gpu_fetch(mold_gpu_points, indices.x*2);
    vec4 a = mold_gpu_fetch(mold_gpu_points, indices.y*2);
    vec4 b = mold_gpu_fetch(mold_gpu_points, indices.z*2);
    vec4 next = mold_gpu_fetch(mold_gpu_points, indices.w*2);
    vec2 cuts=vec2(0.0,1.0);
    int cap=mold_gpu_cap;
    if (mold_gpu_dash.x != 0.0) {
        int slot=local_id/36; local_id=local_id%36;
        bool active=mold_dash_segment(mold_gpu_dash,slot,mold_gpu_fetch(mold_gpu_segments,segment*3+2),previous,a,b,next,metrics,cuts);
        if (!active) {
            position=a.xyz; color=vec4(0.0); uv=vec2(0.0); custom0=vec4(0.0); custom1=vec4(0.0); custom2=vec4(0.0); author_position=a.xyz;
            return;
        }
        if (mold_gpu_dash_cap>=0 && mold_gpu_dash.y>0.0) cap=mold_gpu_dash_cap;
    }
    author_position = mold_stroke_start(local_id) ? a.xyz : b.xyz;
    if (mold_gpu_geometry == 1) {
        float scale = max(length(model[0].xyz),max(length(model[1].xyz),length(model[2].xyz)));
        mold_billboard_vertex(previous,a,b,next,metrics,local_id,mold_gpu_join,cap,mold_gpu_miter_limit,
            model_view,scale,abs(projection[3][3]) < 0.5,mold_stroke_near(projection),position,uv,custom0,custom1,custom2);
        model_view = mat4(1.0);
    } else {
        mold_stroke_vertex(previous,a,b,next,metrics,local_id,mold_gpu_join,cap,mold_gpu_miter_limit,position,uv,custom0,custom1,custom2);
    }
    int point_index = mold_stroke_start(local_id) ? indices.y : indices.z;
    color=mix(mold_gpu_fetch(mold_gpu_points,indices.y*2+1),mold_gpu_fetch(mold_gpu_points,indices.z*2+1),mold_stroke_start(local_id) ? cuts.x : cuts.y);
}
