import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import struct
import tempfile
import unittest
import zipfile
import zlib

BASE = Path(__file__).resolve().parents[1]
def module(name):
    spec = importlib.util.spec_from_file_location(name, BASE/'scripts'/(name+'.py'))
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value
workflow = module('check_workflow')
exports = module('check_exports')

class WorkflowTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.data = json.loads((BASE/'assets/templates/project.json').read_text())
        f = self.root/'artifact.txt'; f.write_text('actual artifact')
        self.item = {'file':f.name, 'sha256':hashlib.sha256(f.read_bytes()).hexdigest()}
    def tearDown(self): self.tmp.cleanup()
    def accept(self, i):
        s=self.data['stages'][i]
        s.update(status='accepted', scope='test scope', criteria=['inspect artifact'],outputs=[self.item.copy()],
          approval={'quote':'TEST FIXTURE ONLY: accepted artifact', 'message_ref':'fixture/1','time':'fixture','revision':1})
    def test_empty_template_valid_but_not_executable(self):
        self.assertEqual(workflow.check(self.data,self.root),[])
        self.assertTrue(workflow.check(self.data,self.root,'1'))
    def test_stage_gate_requires_predecessor_acceptance(self):
        s=self.data['stages'][1]; s.update(scope='UI scope',criteria=['review pages'])
        self.assertTrue(workflow.check(self.data,self.root,'2'))
        self.accept(0)
        self.assertEqual(workflow.check(self.data,self.root,'2'),[])
    def test_plan_approval_is_not_stage_acceptance(self):
        self.data['stages'][0]['approval']={'quote':'execute the plan','revision':1}
        s=self.data['stages'][1];s.update(scope='scope',criteria=['criterion'])
        self.assertTrue(workflow.check(self.data,self.root,'2'))
    def test_scope_change_invalidates_old_acceptance(self):
        self.accept(0);self.data['stages'][0]['revision']=2
        self.assertTrue(workflow.check(self.data,self.root))
    def test_artifact_change_detected(self):
        self.accept(0);(self.root/'artifact.txt').write_text('changed')
        self.assertTrue(workflow.check(self.data,self.root))
    def test_path_escape_rejected(self):
        self.accept(0);self.data['stages'][0]['outputs'][0]['file']='../outside.txt'
        self.assertTrue(workflow.check(self.data,self.root))
    def test_dependency_cycle_rejected(self):
        self.data['stages'][0]['requires']=['2']
        self.assertTrue(workflow.check(self.data,self.root))
    def test_sources_pages_and_placeholders_checked(self):
        self.data['sources']=[{'id':'user1','type':'user_decision','reference':'test transcript'}]
        self.data['pages']=[{'id':'p','source_ids':['user1']}]
        self.data['interactions']=[{'id':'a','page':'unknown','source_ids':['user1']}]
        self.assertTrue(workflow.check(self.data,self.root))
        self.data['interactions'][0]['page']='p'
        self.data['assets']=[dict(self.item,id='hero',page='p',source_ids=['user1'],status='complete',role='hero',placeholder='icon')]
        self.assertTrue(workflow.check(self.data,self.root))
    def test_no_skipping_required_sdk(self):
        self.data['modules']['meta']=False
        self.assertTrue(workflow.check(self.data,self.root))
    def test_no_configuration_acceptance_invented(self):
        self.accept(0);self.data['stages'][0]['approval']['message_ref']=''
        self.assertTrue(workflow.check(self.data,self.root))
    def test_not_applicable_requires_user_record_and_reason(self):
        self.accept(0)
        s=self.data['stages'][1];s.update(status='not_applicable',approval={'revision':1,'quote':'fixture skip','message_ref':'fixture','time':'fixture'})
        self.assertTrue(workflow.check(self.data,self.root))
        s['na_reason']='scope excludes this step'
        self.assertEqual(workflow.check(self.data,self.root),[])
    def test_all_ten_stages_must_be_retained(self):
        for stages in [[], self.data['stages'][:2], self.data['stages'][:-1]]:
            with self.subTest(count=len(stages)):
                data=copy.deepcopy(self.data);data['stages']=stages
                self.assertTrue(workflow.check(data,self.root))
    def test_unknown_and_invalid_stage_ids_rejected(self):
        for sid in ['11', 1, None, []]:
            with self.subTest(sid=sid):
                data=copy.deepcopy(self.data);data['stages'][0]['id']=sid
                self.assertTrue(workflow.check(data,self.root))
    def test_revision_requires_positive_integer_even_when_values_match(self):
        self.accept(0)
        for revision in [0, -1, True, 1.0, '1', None, []]:
            with self.subTest(revision=revision):
                data=copy.deepcopy(self.data)
                data['stages'][0]['revision']=revision
                data['stages'][0]['approval']['revision']=revision
                self.assertTrue(workflow.check(data,self.root))
    def test_approval_revision_cannot_use_bool_or_float(self):
        self.accept(0)
        for revision in [True, 1.0]:
            data=copy.deepcopy(self.data);data['stages'][0]['approval']['revision']=revision
            self.assertTrue(workflow.check(data,self.root))
    def test_blank_scope_and_each_criterion_rejected(self):
        stage=self.data['stages'][0]
        for scope,criteria in [('  ',['inspect']),('scope',['  ']),('scope',['inspect','']),
                               ('scope','inspect'),(True,['inspect']),('scope',[1])]:
            with self.subTest(scope=scope,criteria=criteria):
                stage.update(scope=scope,criteria=criteria)
                self.assertTrue(workflow.check(self.data,self.root,'1'))
        stage.update(scope=' scoped ',criteria=[' inspect '])
        self.assertEqual(workflow.check(self.data,self.root,'1'),[])
    def test_blank_approval_and_skip_reason_rejected(self):
        self.accept(0)
        for key in ['quote','message_ref','time']:
            data=copy.deepcopy(self.data);data['stages'][0]['approval'][key]='  '
            self.assertTrue(workflow.check(data,self.root))
        self.data['stages'][0].update(status='not_applicable',na_reason='  ')
        self.assertTrue(workflow.check(self.data,self.root))
    def test_predecessor_gate_cannot_be_removed(self):
        self.data['stages'][1].update(requires=[],scope='scope',criteria=['inspect'])
        self.assertTrue(workflow.check(self.data,self.root,'2'))
    def test_stage_order_does_not_depend_on_array_order(self):
        self.data['stages'].reverse()
        self.assertEqual(workflow.check(self.data,self.root),[])
    def test_invalid_stage_container_returns_errors(self):
        for stages in [None, {}, ['1']]:
            data=copy.deepcopy(self.data);data['stages']=stages
            self.assertTrue(workflow.check(data,self.root))

def png(width,height):
    def chunk(kind,data): return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data)&0xffffffff)
    return b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',width,height,8,6,0,0,0))+chunk(b'IDAT',zlib.compress((b'\x00'+b'\xff\x00\x00\xff'*width)*height))+chunk(b'IEND',b'')

class ExportTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.root=Path(self.tmp.name)
        self.blob=png(2,3);(self.root/'logo.png').write_bytes(self.blob)
        self.data={'assets':[{'file':'logo.png','sha256':hashlib.sha256(self.blob).hexdigest(),'width':2,'height':3,'alpha_channel':True}]}
    def tearDown(self):self.tmp.cleanup()
    def test_dimensions_and_alpha(self):
        self.assertEqual(exports.check(self.data,self.root),[])
        self.data['assets'][0]['width']=3
        self.assertTrue(exports.check(self.data,self.root))
    def test_crc_corruption_detected(self):
        blob=bytearray(self.blob);blob[-1]^=1
        with self.assertRaises(ValueError):exports.png_info(blob)
    def test_flat_zip_exact_members_and_content(self):
        p=self.root/'bundle.zip'
        with zipfile.ZipFile(p,'w')as z:z.writestr('logo.png',self.blob)
        self.data['zip']={'file':'bundle.zip','members':['logo.png']}
        self.assertEqual(exports.check(self.data,self.root),[])
        with zipfile.ZipFile(p,'w')as z:z.writestr('logo.png',png(4,5))
        self.assertTrue(exports.check(self.data,self.root))
    def test_nested_extra_zip_rejected(self):
        with zipfile.ZipFile(self.root/'bundle.zip','w')as z:z.writestr('folder/logo.png',self.blob)
        self.data['zip']={'file':'bundle.zip','members':['folder/logo.png']}
        self.assertTrue(exports.check(self.data,self.root))

if __name__=='__main__':unittest.main()
