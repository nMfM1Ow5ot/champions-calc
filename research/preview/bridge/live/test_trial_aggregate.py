import unittest
from run_trial import summarize, descendants

def sample(status,gate=True,n=1):
    d='a'*64
    r={'frame':n,'frame_sha256':d,'legacy_gate':gate,'legacy_names':['Pikachu']*6 if gate else [],'legacy_gate_ms':10,'legacy_rank_ms':20,'snapshot_age_ms':30,'new_status':status,'accepted':False}
    if status in ('ranked','held','error'):
        r['new_exchange_ms']=40
        r['new_result']={'accepted':False,'scene_authenticated':False,'frame_sha256':d,'status':status,'slots':[[['pikachu',.2]]]*6 if status=='ranked' else [None]*6,'route':'full_layout_candidate' if status=='ranked' else None}
    return r

def envelope(rows):return {'schema':'pv16-live-trial-v1','scope':'read_only_ring_per_frame','accepted':False,'frames':rows,'polls':{},'warmup_ms':1,'sampling_elapsed_ms':1,'worker_cleaned':True,'state_paths_absent':True}

class Cases(unittest.TestCase):
    def test_pair(self):
        o=summarize(envelope([sample('ranked'),sample('held',False,2)]));self.assertTrue(o['limited_transport_pass']);self.assertEqual(o['normalized_id_agreement'],6);self.assertTrue(o['mixed_scene_evidence']);self.assertFalse(o['independent_accuracy_measured'])
    def test_busy(self):
        o=summarize(envelope([sample('ranked'),sample('busy',True,2)]));self.assertEqual(o['submitted'],1);self.assertEqual(o['new_status']['busy'],1)
    def test_failure(self):self.assertFalse(summarize(envelope([sample('bridge_failure')]))['limited_transport_pass'])
    def test_no_frames(self):self.assertFalse(summarize(envelope([]))['limited_transport_pass'])
    def test_confirmation_rejected(self):
        r=sample('ranked');r['new_result']['accepted']=True
        with self.assertRaises(AssertionError):summarize(envelope([r]))
    def test_digest_rejected(self):
        r=sample('ranked');r['new_result']['frame_sha256']='wrong'
        with self.assertRaises(AssertionError):summarize(envelope([r]))
    def test_no_cleanup(self):
        v=envelope([sample('ranked')]);v['worker_cleaned']=False;self.assertFalse(summarize(v)['limited_transport_pass'])
    def test_descendants(self):self.assertEqual(descendants({1:(0,0,1),2:(1,0,1),3:(2,0,1),9:(0,0,1)},1),{1,2,3})
    def test_state_paths(self):
        v=envelope([sample('ranked')]);v['state_paths_absent']=False;self.assertFalse(summarize(v)['limited_transport_pass'])
if __name__=='__main__':unittest.main()
