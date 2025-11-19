import logging
import subprocess
import json
import os
from pygeoapi.process.base import BaseProcessor, ProcessorExecuteError

LOGGER = logging.getLogger(__name__)

script_title_and_path = __file__
metadata_title_and_path = script_title_and_path.replace('.py', '.json')
PROCESS_METADATA = json.load(open(metadata_title_and_path))

'''
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

    def set_job_id(self, job_id: str):
        self.my_job_id = job_id

    def __repr__(self):
        return f'<CombineEurostatDataProcessor> {self.name}'

    def execute(self, data, outputs=None):
        config_file_path = os.environ.get('DAUGAVA_CONFIG_FILE', "./config.json")
        with open(config_file_path, 'r') as configFile:
            configJSON = json.load(configFile)
            self.download_dir = configJSON["download_dir"].rstrip('/')
            self.download_url = configJSON["download_url"].rstrip('/')

        # Where to store output data (will be mounted read-write into container):
        output_dir = f'{self.download_dir}/out/{self.process_id}/job_{self.my_job_id}'
        output_url = f'{self.download_url}/out/{self.process_id}/job_{self.my_job_id}'
        os.makedirs(output_dir, exist_ok=True)

        # User inputs
        in_country_code = data.get('country_code')
        in_year = data.get('year')

        # Check user inputs
        if in_country_code is None:
            raise ProcessorExecuteError('Missing parameter "inputFile_tif". Please provide a inputFile_tif.')
        if in_year is None:
            raise ProcessorExecuteError('Missing parameter "year". Please provide a year.')

        # Where to store output data
        downloadfilename = 'nuts3_pop_data-%s.gpkg' % self.my_job_id

        returncode, stdout, stderr = run_docker_container(
            self.image_name,
            in_country_code,
            in_year,
            output_dir,
            downloadfilename
        )

        if not returncode == 0:
            err_msg = 'Running docker container failed.'
            for line in stderr.split('\n'):
                if line.startswith('Error'):
                    err_msg = 'Running docker container failed: %s' % (line)
            raise ProcessorExecuteError(user_msg = err_msg)

        else:
            # Create download link:
            downloadlink = output_url.rstrip('/')+os.sep+downloadfilename

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


def run_docker_container(
        image_name,
        in_country_code,
        in_year,
        local_out,
        downloadfilename
    ):

    LOGGER.debug('Prepare running docker container (image: %s)' % image_name)
    container_name = f'{image_name.split(':')[0]}_{os.urandom(5).hex()}'

    # Mounting
    container_out = '/out'

    script = 'combine_eurostat_data.R'

    docker_command = [
        "docker", "run", "--rm", "--name", container_name,
        "-v", f"{local_out}:{container_out}",
        "-e", f"R_SCRIPT={script}",
        image_name,
        in_country_code,
        in_year,
        f"{container_out}/{downloadfilename}"
    ]

    # Run container
    try:
        LOGGER.debug('Start running docker container (image: %s, name: %s)' % (image_name, container_name))

        result = subprocess.run(docker_command, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        LOGGER.debug('Finished running docker container (image: %s, name: %s)' % (image_name, container_name))

        # Print and return docker output:
        stdout = result.stdout.decode()
        stderr = result.stderr.decode()
        return result.returncode, stdout, stderr

    except subprocess.CalledProcessError as e:
        return e.returncode, e.stdout.decode(), e.stderr.decode()