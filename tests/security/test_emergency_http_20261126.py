import ast, functools, http.server, os, pathlib, sys, tempfile, threading, urllib.request, urllib.error, unittest

class SecurityTest(unittest.TestCase):
    def test_http(self):
        source = pathlib.Path(sys.argv[1]).read_text()
        tree = ast.parse(source)
        cls = next(n for n in tree.body if isinstance(n, ast.ClassDef) and n.name == 'QuietHandler')
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)/'public'; root.mkdir()
            files = {'ui.html':'ui','state.json':'{}','my_team.json':'{}','presets.json':'{}','data/a.json':'{}','github_log_token.txt':'DUMMY','team_key.txt':'DUMMYKEY','.git/config':'dummy','.env':'dummy','.env.local':'dummy','a.pem':'dummy','a.key':'dummy','a.p12':'dummy','a.pfx':'dummy','normal/index.html':'index','empty/a.txt':'a'}
            for name, body in files.items():
                p=root/name; p.parent.mkdir(parents=True,exist_ok=True); p.write_text(body)
            (root/'alias').symlink_to(root/'team_key.txt'); os.link(root/'team_key.txt',root/'hardalias')
            outside=pathlib.Path(tmp)/'outside'; outside.write_text('dummy'); (root/'outside').symlink_to(outside)
            (root/'badindex').mkdir(); (root/'badindex/index.html').symlink_to(root/'team_key.txt')
            ns={'http':http,'os':os,'LOG_TOKEN_PATH':str(root/'github_log_token.txt'),'LOG_KEY_PATH':str(root/'team_key.txt')}
            exec(compile(ast.Module(body=[cls],type_ignores=[]),'<handler>','exec'),ns)
            server=http.server.ThreadingHTTPServer(('127.0.0.1',0),functools.partial(ns['QuietHandler'],directory=str(root)))
            t=threading.Thread(target=server.serve_forever,daemon=True); t.start()
            try:
                cases=[(p,200,b.encode()) for p,b in files.items() if p in ('ui.html','state.json','my_team.json','presets.json','data/a.json','normal/index.html')]
                cases += [(p,404,None) for p in ('github_log_token.txt','team_key.txt','.git/config','.env','.env.local','a.pem','a.key','a.p12','a.pfx','alias','hardalias','outside','badindex/','%74eam_key.txt','data/../team_key.txt')]
                cases += [('empty/',403,None),('normal/',200,b'index')]
                for path,status,body in cases:
                    with self.subTest(path=path):
                        try:
                            with urllib.request.urlopen(f'http://127.0.0.1:{server.server_port}/{path}',timeout=3) as r: got=r.status; data=r.read()
                        except urllib.error.HTTPError as e: got=e.code; data=e.read()
                        self.assertEqual(got,status)
                        if body is not None: self.assertEqual(data,body)
                        print(f'{path}: {got}')
            finally: server.shutdown(); server.server_close(); t.join()

if __name__=='__main__': unittest.main(argv=[sys.argv[0]])
