#include <plan_env/raycast.h>
#include <cmath>
#include <iostream>
#include <stdexcept>
#include <random>

static void require(bool condition, const char* message) {
  if (!condition) throw std::runtime_error(message);
}

static Eigen::Vector3d center(const Eigen::Vector3i& index,
                              const Eigen::Vector3d& origin, double resolution) {
  return origin + (index.cast<double>() + Eigen::Vector3d::Constant(0.5)) * resolution;
}

static void axisRay(const Eigen::Vector3d& origin, int sign) {
  const double resolution = 0.15;
  const Eigen::Vector3i first(200, 266, 66);
  const Eigen::Vector3i last = first + Eigen::Vector3i(sign * 4, 0, 0);
  RayCaster ray;
  ray.setParams(resolution, origin);
  require(ray.input(center(first, origin, resolution), center(last, origin, resolution)), "nonempty ray rejected");
  Eigen::Vector3i index;
  for (int i = 0; i < 4; ++i) {
    require(ray.nextId(index), "ray ended early");
    require(index == first + Eigen::Vector3i(sign * i, 0, 0), "ray index disagrees with map index");
  }
  require(!ray.nextId(index), "endpoint should be excluded");
  require(index == last, "wrong endpoint index");

  ray.input(center(first, origin, resolution), center(last, origin, resolution));
  Eigen::Vector3d position;
  require(ray.nextPos(position), "position ray ended early");
  require((position - center(first, origin, resolution)).norm() < 1e-9, "world position ignores map origin");

  ray.biInput(center(first, origin, resolution), center(last, origin, resolution));
  Eigen::Vector3i backward;
  require(ray.biNextId(index, backward), "bidirectional ray ended early");
  require(index == first && backward == last, "bidirectional indices disagree with map");
}

int main() {
  try {
    for (const auto& origin : {Eigen::Vector3d::Zero().eval(),
                              Eigen::Vector3d(-30, -40, -3),
                              Eigen::Vector3d(-30.000001, -40.000001, -3),
                              Eigen::Vector3d(0.07, 0.02, 0.04)}) {
      axisRay(origin, 1);
      axisRay(origin, -1);
    }
    // Fractional endpoints make X cross first; integer direction deltas choose Y.
    RayCaster ray;
    ray.setParams(1.0, Eigen::Vector3d::Zero());
    ray.input(Eigen::Vector3d(0.1, 0.8, 0.5), Eigen::Vector3d(1.9, 1.01, 0.5));
    Eigen::Vector3i index;
    require(ray.nextId(index) && index == Eigen::Vector3i(0, 0, 0), "wrong start cell");
    require(ray.nextId(index) && index == Eigen::Vector3i(1, 0, 0), "missed first crossed cell");
    require(!ray.nextId(index) && index == Eigen::Vector3i(1, 1, 0), "wrong final cell");
    ray.input(Eigen::Vector3d(0.9, 0.5, 0.5), Eigen::Vector3d(1.1, 0.5, 0.5));
    require(ray.nextId(index) && index == Eigen::Vector3i(0, 0, 0), "sub-voxel crossing failed");
    require(!ray.nextId(index), "sub-voxel crossing did not terminate");
    require(!ray.input(Eigen::Vector3d(0.1, 0.1, 0.1), Eigen::Vector3d(0.2, 0.2, 0.2)), "same-cell ray must be empty");
    require(!ray.nextId(index), "same-cell ray produced a cell");
    // Every step must approach the endpoint, including negative rays whose
    // endpoints lie on voxel faces and rays with nearly parallel components.
    std::mt19937 generator(42);
    std::uniform_real_distribution<double> sample(-30.0, 30.0);
    const Eigen::Vector3d origin(-30, -40, -3);
    ray.setParams(0.15, origin);
    for (int test = 0; test < 3000; ++test) {
      Eigen::Vector3d from(sample(generator), sample(generator), sample(generator));
      Eigen::Vector3d to(sample(generator), sample(generator), sample(generator));
      if (test % 3 == 0) from.x() = 0.0;
      if (test % 5 == 0) to.y() = from.y() + 1e-12;
      const Eigen::Vector3i first = ((from-origin)/0.15).array().floor().cast<int>();
      const Eigen::Vector3i last = ((to-origin)/0.15).array().floor().cast<int>();
      int remaining = (last-first).cwiseAbs().sum();
      ray.input(from, to);
      while (ray.nextId(index)) {
        require((last-index).cwiseAbs().sum() == remaining, "ray stepped away from endpoint");
        require(remaining-- > 0, "ray did not terminate");
      }
      require(remaining == 0 && index == last, "ray skipped endpoint");
    }
    std::cout << "Raycaster map-origin and traversal tests passed\n";
  } catch (const std::exception& error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}
