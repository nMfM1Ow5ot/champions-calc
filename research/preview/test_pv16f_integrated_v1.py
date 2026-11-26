"""Synthetic contracts only; no image assets, labels, network or production use."""
import unittest
from dataclasses import replace
from itertools import permutations
from unittest.mock import patch
from types import SimpleNamespace
import numpy as np
import pv16f_coverage_v2 as cov
import pv16f_joint_candidate_v2 as core
import pv16f_integrated_v1 as m

IDS=tuple("p%02d"%i for i in range(10))
C=m.Contract(m.catalog_digest(IDS),*["1"*64]*6)
R=[(a,float(i+1)) for i,a in enumerate(IDS)]
def frame(k="f1",c=C,s="s1",row=R):
    return dict(contract=c,session=s,frame_id=k,slots=[row]*6,accepted=False)
def boundary(c=C,points=((2.,),)):
    return m.Boundary(c.digest,("distance",),points,"2"*64)

class ContractTests(unittest.TestCase):
    def test_iterator_block(self):
        for b in ([(.5,)],iter([(.5,)])):
            self.assertFalse(cov.propose(R,IDS,("distance",),b,True)["would_accept"])
    def test_iterator_empty_and_safe(self):
        self.assertFalse(cov.propose(R,IDS,("distance",),iter([]),True)["would_accept"])
        self.assertTrue(cov.propose(R,IDS,("distance",),iter([(2.,)]),True)["would_accept"])
    def test_no_boundary(self):
        self.assertFalse(m.propose_slot(frame(),IDS,0,context_valid=True)["would_accept"])
    def test_boundary_bound_to_score_domain(self):
        for key in ("ranker_digest","reference_digest","gallery_digest","geometry_digest","sampling_digest","typebank_digest"):
            c=replace(C,**{key:"3"*64})
            with self.assertRaises(ValueError):m.propose_slot(frame(c=c),IDS,0,boundary(),True)
        fused=m.fuse_frames([frame()],IDS,C)
        with self.assertRaises(ValueError):m.propose_slot(fused,IDS,0,boundary(),True)
        result=m.propose_slot(fused,IDS,0,boundary(fused["contract"]),True)
        self.assertTrue(result["would_accept"]);self.assertFalse(result["accepted"])
    def test_non_distance_contract(self):
        for kind in ("borda","plurality"):
            with self.assertRaises(ValueError):replace(C,score_kind=kind)
    def test_mixed_revision(self):
        with self.assertRaises(ValueError):m.fuse_frames([frame(),frame("f2",replace(C,reference_digest="3"*64))],IDS,C)
    def test_mixed_session_and_conflict(self):
        with self.assertRaises(ValueError):m.fuse_frames([frame(),frame("f2",s="s2")],IDS,C)
        with self.assertRaises(ValueError):m.fuse_frames([frame(),frame(row=[(a,d+1) for a,d in R])],IDS,C)
    def test_duplicate_reorder(self):
        f,g=frame(),frame("f2",row=[(a,d+2) for a,d in R])
        self.assertEqual(m.fuse_frames([f,g],IDS,C),m.fuse_frames([g,f,f],IDS,C))
    def test_bad_distance(self):
        with self.assertRaises(ValueError):m.fuse_frames([frame(row=[(a,-d) for a,d in R])],IDS,C)
    def test_missing_context(self):
        self.assertFalse(m.propose_slot(frame(),IDS,0,boundary(),False)["would_accept"])
    def test_tie(self):
        rank=[(a,1.) for a in IDS]
        self.assertFalse(m.propose_slot(frame(row=rank),IDS,0,boundary(),True)["would_accept"])
    def test_geometry_rejected(self):
        with self.assertRaises(ValueError):m.rank_frame(SimpleNamespace(ids=IDS),None,None,None,C,"s","f")
    def test_blank_gallery_descriptor(self):
        im=np.zeros((540,823,3),np.uint8)
        self.assertIsNone(m.descriptor(im,core.YS[0]))
        self.assertIsNone(core.encode(im,core.YS[0]))
    def test_fallback_guard(self):
        im=np.zeros((540,823,3),np.uint8)
        # Initial background differs from entire uniform sprite region.
        im[core.YS[0]+4,737]=255
        self.assertIsNone(core.encode(im,core.YS[0]))
    def test_gallery_bonus(self):
        im=np.zeros((540,823,3),np.uint8)
        y=core.YS[0];im[y+10:y+32,680:700]=(30,130,220)
        q=m.descriptor(im,y);self.assertIsNotNone(q)
        bank=([IDS[0]],*[a[None,:] for a in q])
        b=m.gallery_bonus(q,bank,IDS)
        self.assertAlmostEqual(b[IDS[0]],.4)
        self.assertEqual(b[IDS[1]],0.)
    def test_team_unverified_missing_infeasible(self):
        groups={a:a for a in IDS}
        self.assertIsNone(m.team_candidate([R]*6,IDS,groups)["team"])
        self.assertIsNone(m.team_candidate([None]+[R]*5,IDS,groups,True)["team"])
        self.assertIsNone(m.team_candidate([R]*6,IDS,{a:"one" for a in IDS},True)["team"])
    def test_team_dp_vs_bruteforce(self):
        groups={a:str(i//2) if i<4 else a for i,a in enumerate(IDS)}
        rows=[[(a,float((j*13+i*7+j*i)%23)) for i,a in enumerate(IDS)] for j in range(6)]
        d=[dict(r) for r in rows]
        answer=m.team_candidate(rows,IDS,groups,True)
        best=min(sum(d[j][a] for j,a in enumerate(t)) for t in permutations(IDS,6) if len({groups[a] for a in t})==6)
        self.assertEqual(answer["cost"],best)
        self.assertEqual(len({groups[a] for a in answer["team"]}),6)
        self.assertFalse(answer["accepted"])
    def test_team_tie(self):
        out=m.team_candidate([[(a,1.) for a in IDS]]*6,IDS,{a:a for a in IDS},True)
        self.assertTrue(out["tie"]);self.assertFalse(out["accepted"])

if __name__=="__main__":unittest.main()
