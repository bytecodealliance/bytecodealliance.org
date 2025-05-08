# Bytecode Alliance Website

This repository contains the source code for the [Bytecode Alliance website](https://bytecodealliance.org/).
The Bytecode Alliance is a nonprofit organization dedicated to creating secure software foundations for the
future of the WebAssembly ecosystem and beyond.

## Website Overview

The Bytecode Alliance website serves as:

- **A hub for WebAssembly technologies:** Learn about WebAssembly and its growing ecosystem.
- **Information on the Bytecode Alliance mission:** Explore the mission, goals, and initiatives of the Bytecode Alliance.
- **A resource for contributors and users:** Access documentation, project updates, and community events.

## Build Locally and Development Environment

We use `jekyll` as a static page generator. If you would like to run a version of the Website locally follow these
instructions.

1. **Install Ruby and Dependencies**: Install [Jekyll Installation Guide](https://jekyllrb.com/docs/installation/). Follow the instructions on the
                official website.
2. **Install Project Dependencies**: `bundle install`
3. **Run**: `bundle exec jekyll serve`

### Use Docker
By using Docker Containers you don't have to install any Ruby Environment on your local machine. Do run the Blog
locally using Docker issue the following steps:

1. Build the Image
```bash
docker build -t my/bablog .
```
2. Run the Development Server
```bash
docker run -v ./:/blog/ -p 4000:4000 -t my/bablog
```

## Contribution Guide

We welcome contributions to improve the website! To get started:

1. **Fork this repository**: Create your own copy of the repository.
2. **Clone the repository**: Use `git clone` to copy it to your local machine.
3. **Set up your environment**: Follow the setup instructions in [`/.github/CONTRIBUTING.md`](.github/CONTRIBUTING.md).
4. **Submit a pull request**: Push your changes and open a pull request to the `main` branch.

Please ensure all contributions adhere to our [Code of Conduct](.github/ORG_CODE_OF_CONDUCT.md).

## License

This repository is licensed under the [Apache 2.0 License](LICENSE).
By contributing to this repository, you agree to license your contributions under the same license.

## Getting Help

If you encounter any issues or have questions, please open an issue in this repository or reach out via the contact information on the [website](https://bytecodealliance.org/).

## Acknowledgments

The Bytecode Alliance is grateful to its contributors and the community for their support and collaboration. Together, we are building a stronger, more secure WebAssembly ecosystem.
