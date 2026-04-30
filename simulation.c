/* ************************************************************************** */
/*                                                                            */
/*                                                        :::      ::::::::   */
/*   simulation.c                                       :+:      :+:    :+:   */
/*                                                    +:+ +:+         +:+     */
/*   By: ccakir <ccakir@student.42.fr>              +#+  +:+       +#+        */
/*                                                +#+#+#+#+#+   +#+           */
/*   Created: 2026/04/29 22:44:25 by ccakir            #+#    #+#             */
/*   Updated: 2026/04/30 22:43:11 by ccakir           ###   ########.fr       */
/*                                                                            */
/* ************************************************************************** */

#include "./philosophers.h"

int	is_dead(t_table *table)
{
	int	is_dead;

	pthread_mutex_lock(&table->dead_mutex);
	is_dead = table->is_someone_dead;
	pthread_mutex_unlock(&table->dead_mutex);
	return (is_dead);
}

void	take_forks(t_philo *philo)
{
	int	left;
	int	right;

	left = philo->id - 1;
	right = philo->id % philo->table->philo_count;
	if (philo->id % 2 == 0)
	{
		pthread_mutex_lock(&philo->table->forks[left]);
		if (!is_dead(philo->table))
			print_action(philo, "has taken a fork.");
		pthread_mutex_lock(&philo->table->forks[right]);
		if (!is_dead(philo->table))
			print_action(philo, "has taken a fork.");
	}
	else
	{
		pthread_mutex_lock(&philo->table->forks[right]);
		if (!is_dead(philo->table))
			print_action(philo, "has taken a fork.");
		pthread_mutex_lock(&philo->table->forks[left]);
		if (!is_dead(philo->table))
			print_action(philo, "has taken a fork.");
	}
}


void	put_forks(t_philo *philo)
{
	int	left;
	int	right;

	left = philo->id - 1;
	right = philo->id % philo->table->philo_count;
	pthread_mutex_unlock(&philo->table->forks[left]);
	pthread_mutex_unlock(&philo->table->forks[right]);
}

static void	*philo_routine(void *arg)
{
	t_philo	*philo;

	philo = (t_philo *)arg;
	if (philo->id % 2 == 0)
		ft_usleep(philo->table->time_to_eat / 2);
	while (1)
	{
		if (is_dead(philo->table))
			return (NULL);
		if (!is_dead(philo->table))
			eat(philo);
		if (!is_dead(philo->table))
		{
			print_action(philo, "is sleeping");
			ft_usleep(philo->table->time_to_sleep);
		}
		if (!is_dead(philo->table))
		{
			print_action(philo, "is thinking");
			ft_usleep(1);
		}
	}
	return (NULL);
}

int	start_simulation(t_table *table)
{
	int			i;
	pthread_t	monitor_thread;

	if (table->philo_count == 1)
	{
		print_action(&table->philos[0], "has taken a fork");
		ft_usleep(table->time_to_die);
		print_action(&table->philos[0], "died");
		return (0);
	}
	pthread_create(&monitor_thread, NULL, monitor, table);
	table->threads = malloc(sizeof(pthread_t) * table->philo_count);
	if (!table->threads)
		return (1);
	i = -1;
	while (++i < table->philo_count)
		pthread_create(&table->threads[i], NULL,
			philo_routine, &table->philos[i]);
	i = -1;
	while (++i < table->philo_count)
		pthread_join(table->threads[i], NULL);
	pthread_join(monitor_thread, NULL);
	return (0);
}
