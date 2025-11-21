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

'''
# TESTED 2025-11-19
curl -X POST https://${PYSERVER}/processes/combine-eurostat-data/execution \
  --header 'Prefer: respond-async;return=representation' \
  --header 'Content-Type: application/json' \
  --data '{
    "inputs": {
      "country_code": "DE",
      "year": "2021"
    }
}'
'''

class CombineEurostatDataProcessor(BaseProcessor):

    def __init__(self, processor_def):
        super().__init__(processor_def, PROCESS_METADATA)
        self.supports_outputs = True
        self.process_id = self.metadata["id"]
        self.my_job_id = 'nothing-yet'
        self.image_name = 'aquainfra-elbe-usecase-image:20251119'
        self.script_name = 'combine_eurostat_data.R'


    def set_job_id(self, job_id: str):
        self.my_job_id = job_id

    def __repr__(self):
        return f'<CombineEurostatDataProcessor> {self.name}'

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
        in_country_code = data.get('country_code')
        in_nuts_year = data.get('nuts_year')
        in_pop_year = data.get('pop_year')

        # Check user inputs
        if in_country_code is None:
            raise ProcessorExecuteError('Missing parameter "inputFile_tif". Please provide a inputFile_tif.')
        if in_nuts_year is None:
            raise ProcessorExecuteError('Missing parameter "nuts_year". Please provide a nuts_year.')
        if in_pop_year is None:
            raise ProcessorExecuteError('Missing parameter "pop_year". Please provide a pop_year.')

        # Where to store output data
        downloadfilename = 'nuts3_pop_data-%s.gpkg' % self.my_job_id
        downloadfilepath = f'{output_dir}/{downloadfilename}'
        downloadlink     = f'{output_url}/{downloadfilename}'

        # Assemble args for script:
        script_args = [in_country_code, in_nuts_year, in_pop_year, downloadfilepath]

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
                    "nuts3_pop_data": {
                        "title": self.metadata['outputs']['nuts3_pop_data']['title'],
                        "description": self.metadata['outputs']['nuts3_pop_data']['description'],
                        "href": f'{downloadlink}'
                    }
                }
            }

            return 'application/json', response_object

