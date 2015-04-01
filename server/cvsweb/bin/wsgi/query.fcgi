#!/usr/bin/python
# -*-python-*-
#
# Copyright (C) 1999-2010 The ViewCVS Group. All Rights Reserved.
#
# By using this file, you agree to the terms and conditions set forth in
# the LICENSE.html file which can be found at the top level of the ViewVC
# distribution or at http://viewvc.org/license-1.html.
#
# For more information, visit http://viewvc.org/
#
# -----------------------------------------------------------------------
#
# viewvc: View CVS/SVN repositories via a web browser
#
# -----------------------------------------------------------------------
#
# This is a fcgi entry point for the query ViewVC app. It's appropriate
# for use with mod_fcgid and flup. It defines a single application function
# that is a valid fcgi entry point.
#
# mod_fcgid: http://httpd.apache.org/mod_fcgid/
# flup:
#   http://pypi.python.org/pypi/flup
#   http://trac.saddi.com/flup
#
# -----------------------------------------------------------------------

import sys, os

LIBRARY_DIR = r"/www/cvsbackup/lib"
CONF_PATHNAME = r"/www/cvsbackup/viewvc.conf"

if LIBRARY_DIR:
  sys.path.insert(0, LIBRARY_DIR)
else:
  sys.path.insert(0, os.path.abspath(os.path.join(sys.argv[0],
                                                  "../../../lib")))

import sapi
import viewvc
import query
from flup.server import fcgi

def application(environ, start_response):
  server = sapi.WsgiServer(environ, start_response)
  cfg = viewvc.load_config(CONF_PATHNAME, server)
  viewvc_base_url = cfg.query.viewvc_base_url
  if viewvc_base_url is None:
    viewvc_base_url = "viewvc.fcgi"
  query.main(server, cfg, viewvc_base_url)
  return []

fcgi.WSGIServer(application).run()
