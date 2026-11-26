"""Frozen F research candidate; offline only. No observation acceptance or IPC.
Caller supplies local PV11 calibration. Do not derive calibration from evaluation images.
Dependencies: pinned PV16 v2 gate, historical PV11, original rank kernel.
"""
import cv2
import numpy as np
import pv16f_scene_gate_v2 as gate
import pv11_scene_dedup_v1 as pv11
import pv16_shadow_worker as worker

SCHEMA="pv16-pv11-hybrid-research-v1"
YS=(97,151,204,258,312,366)

def validate_template(t):
    if not isinstance(t,np.ndarray) or t.dtype!=np.float32 or t.shape!=(32,350):
        raise ValueError("invalid calibration contract")
    if not np.all((t==0)|(t==1)) or not 50<=float(t.sum())<=t.size*.8:
        raise ValueError("invalid calibration mask")
    t=t.copy()
    t.flags.writeable=False
    return t

def fixed_canvas(im,panels):
    if len(panels)!=6:return None
    dst=np.zeros((540,823,3),np.uint8)
    h0,w0=im.shape[:2]
    for y,(x,yy,w,h) in zip(YS,panels):
        if min(x,yy)<0 or min(w,h)<=0 or x+w>w0 or yy+h>h0:return None
        dst[y:y+48,667:795]=cv2.resize(im[yy:yy+h,x:x+w],(128,48),interpolation=cv2.INTER_AREA)
    return dst

class Hybrid:
    def __init__(self,calibration):
        self.template=validate_template(calibration)

    def geometry(self,im):
        if not isinstance(im,np.ndarray) or im.dtype!=np.uint8 or im.ndim!=3 or im.shape[2]!=3:
            return "held",None,"invalid_input"
        g,a=gate.inspect(im)
        if a is not None:return "full",a,"full_layout_candidate"
        if g["layout_candidate"]:return "held",None,"explicit_visibility_rejection"
        if im.shape!=(1080,1920,3):return "held",None,"pv11_unsupported_resolution"
        hit,_=pv11.scene(im,self.template)
        if hit is None:return "held",None,"pv11_no_unique_layout"
        a=fixed_canvas(im,hit[2])
        if a is None:return "held",None,"invalid_panel_bounds"
        if not all(gate.visibility(a)[0]):return "held",None,"sprite_flat_patch"
        return "pv11_fixed_visible",a,"pv11_layout_"+str(hit[1])

    def analyze(self,im,r,local,gb):
        route,a,reason=self.geometry(im)
        result={"schema":SCHEMA,"route":route,"reason":reason,
                "status":"held" if a is None else "ranked",
                "accepted":False,"scene_authenticated":False,
                "slots":[None]*6,"types":None,"recovered":None}
        if a is not None:
            ranks,types,recovered=worker.rank_unconfirmed(r,a,local,gb)
            if len(ranks)!=6 or len(types)!=6 or len(recovered)!=6:
                raise ValueError("rank result contract failure")
            result.update(slots=[row[:5] if row else None for row in ranks],
                          types=types,recovered=recovered)
        return result
