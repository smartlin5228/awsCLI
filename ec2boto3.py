#!/usr/bin/env python

import argparse
import sys
import time
import ConfigParser
import random

import boto3
import boto3.session
import botocore

import paramiko

from collections import defaultdict
from paramiko.ssh_exception import *
from test import pystone

def parse_argv():
    parser = argparse.ArgumentParser(formatter_class=argparse.ArgumentDefaultsHelpFormatter)
    
    parser.add_argument("--config", metavar='PATH', type=str,
                        default='ec2_benchmark.cfg', help='config file')
    
    parser.add_argument("--profile", metavar="NAME", type=str,
                        default='t_series', help='benchmark profile')
    
    parser.add_argument("--wait", action="store_true", help="benchmark profile")

    parser.add_argument("--retry", metavar="NUM", type=int, default=3,
                        help="number of retries")
    # - Use dry run to check if the permission is granted
    parser.add_argument("--dryrun", action="store_true", help="dry run, nothing will be executed")
    
    parser.add_argument("--verbose", metavar='INT', type=int, default=0,
                        help="output verbosity")
    
    parser.add_argument("--clean", dest='clean', action='store_true',
                        default=False, help='clean up Benchmark enviroment')

    args = parser.parse_args()
    return args

# - Class rapper for benchmark functions
class Benchmark:
    def __init__(self, opts):
        self.opts = opts
        self.parse_config(self.opts.config, self.opts.profile)

        self.session = boto3.session.Session()
        self.ec2 = self.session.resource('ec2',
                                         region_name=self.config['region'])
        self.s3 = self.session.resource('s3', region_name=self.config['region'])
        self.tags = defaultdict()
        self.tags['enviroment'] = 'benchmar-%s' % self.opts.profile
        # - use dict to store matching ssh and tags
        self.ssh= defaultdict()
    
    def verbose(self, msg, level=0):
        if self.opts.verbose >= level:
            sys.stdout.write(msg)
            sys.stdout.flush()

    def parse_config(self, cfg, profile):
        self.verbose("Loading configurations from %s with profile %s...\n" %
                     (cfg, profile), 0)
        
        # - Get configuration parser
        self.config = defaultdict(list)
        parser = ConfigParser.RawConfigParser()
        parser.read(cfg)
        
        # - Load default configurations
        self.config = parser.defaults()
        if not parser.has_section(profile):
            self.verbose("Warning: no profile %s found in %s.\n" & (profilem, cfg), 0)
            return
        # - Load profile configuration
        for name, value in parser.items(profile):
            if name == 'intance_type' or name == 'tests':
                self.config[name] = value.split(',')
            else:
                # - check if the intance type exists in profile
                try:
                    self.config[name] = int(value)
                except ValueError:
                    pass # TODO: error prompt
            
            if self.opts.verbose >= 1:
                print " %s: %s = %s " %(profile, name, self.config[name])
    
    def get_instances(self, state='running', instance_types=''):
        instances = self.ec2.instances.filter(Filters=[
            {'Name': 'instance-state-name', 'Values':['running']},
            {'Name': 'tag:enviroment', 'Values':[self.tags['enviroment']]}])
        if instance_types:
            instance_types = instance_types.split(',')
            instances = [instance for instance in instances if \
                         instance.instance_type in instance_types]

        return instances

    def create_instance(instance_type, instance_type, count):
        self.verbose("Creating: %s" % instance_type + \
                    "(ami=%(ami)s, count=%(count)s, key=%(key)s)..." \
                    % self.config, 1)
        launched_instances = defaultdict(list)
        try:
            instances = self.ec2.create_instance(
                DryRun=self.opts.dryrun,
                ImageId=self.config['ami'],
                InstanceType=instance_type,
                MinCount=count,
                MaxCount=count,
                KeyName=self.config['key'],
                SubnetId=self.config['subnet_id'],
                BlockDeviceMappings=[{
                    'DeviceName': '/dev/xvda',
                    'Ebs': {
                        'VolumeSize': 16,
                        'DeleteOnTermination': True,
                        'VolumeType': 'gp2'
                    }
                }])
            for instance in instances:
                instance.create_tags(
                DryRun=self.opts.dryrun,
                    Tags=[{'Key': 'enviroment', 'Value': self.tags['enviroment']}])
            launched_instances[instance_type].extend(instances)
            self.verbose("Successfully launched.\n", 1)
        except botocore.exceptions.ClientError as ce:
            if ce.response['Error'].get('Code') == 'DryRunOperation':
                self.verbose("\n", 1)
            else:
                raise
            return launched_instances


    def launch(self):
        self.verbose("Launching total %s instances..\n" % \
                    (self.config['count'] * \
                     len(self.config['instance_types'])), 0)
        for instance_type in self.config['instance_types']:
            running_instances = self.get_instances(instance_types=instance_type)
            n_running_instances = len(list(running_instances))
            count = self.config['count'] - n_running_instances
            if n_running_instances > 0:
                msg = " %s: %s instances already running, "\
                        % (instance_type, n_running_instances)
                if count == 0:
                    self.verbose(msg + "do nothing.\n", 1)
                elif count > 0:
                    self.verbose(msg + "create %s more.\n", 1)
                    self.create_instance(instance_type, count) # - TODO: create
                else:
                    slef

    def clean(self):
        for instance in self.get_instances():
            self.terminate_instance(instance) # TODO: terminate instances
            bucket = self.s3.Bucket("benchmark-%s" % instance.instance_id)
            self.verbose("deleting bucket %s. \n" % bucket.name)
            for key in bucket.objects.all():
                key.delete()
            bucket.delete()
        
    def run(self):
        if self.opts.clean:
            self.clean()
            return
        
        self.lauch() # - TODO: Lauch instance
        self.configure # - TODO: Instance configuration
        self.do() # - TODO: Helper function, performance check

        if self.opts.dryrun:
            print "Dry run, checking permission while nothing will be executed.\n"
        else:
            print "Done.\n"




        

# - For command line execution
def main():
    b = Benchmark(parse_argv())
    b.run()

if __name__ == '__main__':
    main()
