"""
script for running sqs listener

Created December 21st, 2016
@author: Yaakov Gesher
@version: 0.1.0
@license: Creative Commons (attribution)
"""

# ================
# start imports
# ================

import boto3
import json
import time
import os, sys
from abc import ABCMeta, abstractmethod

# ================
# start class
# ================


class SqsListener(object):
    __metaclass__ = ABCMeta

    def __init__(self, queue, error_queue=None, interval=60, visibility_timeout='600', error_visibility_timeout='600'):
        """
        :param queue: (str) name of queue to listen to
        :param error_queue: (str) optional queue to send exception notifications
        :param interval: (int) number of seconds between each queue polling
        :param visibility_timeout: (str) number of seconds for which the SQS will hide the message.  Typically
                                    this should reflect the maximum amount of time your handler method will take
                                    to finish execution. See http://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-visibility-timeout.html
                                    for more information
        """
        if not os.environ.get('AWS_ACCOUNT_ID', None):
            raise EnvironmentError('Environment variable `AWS_ACCOUNT_ID` not set')
        self._queue_name = queue
        self._poll_interval = interval
        self._queue_visibility_timeout = visibility_timeout
        self._error_queue_name = error_queue
        self._error_queue_visibility_timeout = error_visibility_timeout

    def listen(self):
        sqs = boto3.client('sqs')

        # create queue if necessary
        qs = sqs.get_queue_url(QueueName=self._queue_name, QueueOwnerAWSAccountId=os.environ.get('AWS_ACCOUNT_ID', None))
        if 'QueueUrl' not in qs:
            q = sqs.create_queue(
                QueueName=self._queue_name,
                Attributes={
                    'VisibilityTimeout': self._queue_visibility_timeout  # 10 minutes
                }
            )
            qurl = q['QueueUrl']
        else:
            qurl = qs['QueueUrl']

        # listen to queue
        while True:
            messages = sqs.receive_message(
                QueueUrl=qurl
            )
            if 'Messages' in messages:
                for m in messages['Messages']:
                    receipt_handle = m['ReceiptHandle']
                    m_body = m['Body']
                    attribs = None
                    params_dict = json.loads(m_body)
                    if 'MessageAttributes' in m:
                        attribs = m['MessageAttributes']
                    try:
                        self.handle_message(params_dict, m['Attributes'], attribs)
                        sqs.delete_message(
                            QueueUrl=qurl,
                            ReceiptHandle=receipt_handle
                        )
                    except Exception, ex:
                        print repr(ex)
                        if self._error_queue_name:
                            exc_type, exc_obj, exc_tb = sys.exc_info()
                            print "Pushing exception to error queue"

                            sqs = boto3.client('sqs')

                            # create queue if necessary
                            qs = sqs.get_queue_url(QueueName=self._error_queue_name,
                                                   QueueOwnerAWSAccountId=os.environ.get('AWS_ACCOUNT_ID', None))
                            if 'QueueUrl' not in qs:
                                q = sqs.create_queue(
                                    QueueName=self._error_queue_name,
                                    Attributes={
                                        'VisibilityTimeout': self._error_queue_visibility_timeout  # 10 minutes
                                    }
                                )
                                qurl = q['QueueUrl']
                            else:
                                qurl = qs['QueueUrl']

                            sqs.send_message(
                                QueueUrl=qurl,
                                MessageBody={
                                    'exception_type': str(exc_type),
                                    'error_message': str(ex.args)
                                }
                            )

            else:
                time.sleep(self._poll_interval)

    @abstractmethod
    def handle_message(self, body, attributes, messages_attributes):
        """
        Implement this method to do something with the SQS message contents
        :param body: dict
        :param attributes: dict
        :param messages_attributes: dict
        :return:
        """
        return