import logging
import subprocess
import json
import os
from pygeoapi.process.base import BaseProcessor, ProcessorExecuteError
# how to import python modules containing a hyphen:
import importlib
docker_utils = importlib.import_module("pygeoapi.process.aquainfra-usecase-elbe.src.ogc.docker_utils")



LOGGER = logging.getLogger(__name__)

script_title_and_path = __file__
metadata_title_and_path = script_title_and_path.replace('.py', '.json')
PROCESS_METADATA = json.load(open(metadata_title_and_path))

class ProcessInterpolateLauProcessor(BaseProcessor):

    def __init__(self, processor_def):
        super().__init__(processor_def, PROCESS_METADATA)
        self.supports_outputs = True
        self.process_id = self.metadata["id"]
        self.my_job_id = 'nothing-yet'
        self.image_name = 'aquainfra-elbe-usecase-image:20251119'
        self.script_name = 'process_interpolate_lau.R'

    def set_job_id(self, job_id: str):
        self.my_job_id = job_id

    def __repr__(self):
        return f'<ProcessInterpolateLauProcessor> {self.name}'

    def execute(self, data, outputs=None):
        config_file_path = os.environ.get('AQUAINFRA_CONFIG_FILE', "./config.json")
        with open(config_file_path, 'r') as configFile:
            configJSON = json.load(configFile)
            self.docker_executable = configJSON["docker_executable"]
            self.download_dir = configJSON["download_dir"].rstrip('/')
            self.download_url = configJSON["download_url"].rstrip('/')

        # Where to store output data (will be mounted read-write into container):
        output_dir = f'{self.download_dir}/out/{self.process_id}/job_{self.my_job_id}'
        output_url = f'{self.download_url}/out/{self.process_id}/job_{self.my_job_id}'
        os.makedirs(output_dir, exist_ok=True)

        # User inputs
        in_inputFile1_gpkg = data.get('inputFile1_gpkg')
        in_inputFile2_gpkg = data.get('inputFile2_gpkg')

        # Check user inputs
        if in_inputFile1_gpkg is None:
            raise ProcessorExecuteError('Missing parameter "inputFile1_gpkg". Please provide a inputFile1_gpkg.')
        if in_inputFile2_gpkg is None:
            raise ProcessorExecuteError('Missing parameter "inputFile2_gpkg". Please provide a inputFile2_gpkg.')

        # Where to store output data
        downloadfilename = 'lau_population_errors-%s.gpkg' % self.my_job_id
        downloadfilepath = f'{output_dir}/{downloadfilename}'
        downloadlink     = f'{output_url}/{downloadfilename}'

        # Assemble args for script:
        script_args = [
            in_inputFile1_gpkg,
            in_inputFile2_gpkg,
            downloadfilepath
        ]

        # Run docker container:
        returncode, stdout, stderr, user_err_msg = docker_utils.run_docker_container(
            self.docker_executable,
            self.image_name,
            self.script_name,
            output_dir,
            script_args
        )

        if not returncode == 0:
            user_err_msg = "no message" if len(user_err_msg) == 0 else user_err_msg
            err_msg = 'Running docker container failed: %s' % user_err_msg
            raise ProcessorExecuteError(user_msg = err_msg)

        else:

            # Return link to file:
            response_object = {
                "outputs": {
                    "lau_population_errors": {
                        "title": self.metadata['outputs']['lau_population_errors']['title'],
                        "description": self.metadata['outputs']['lau_population_errors']['description'],
                        "href": f'{downloadlink}'
                    }
                }
            }

            return 'application/json', response_object

