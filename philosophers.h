/* ************************************************************************** */
/*                                                                            */
/*                                                        :::      ::::::::   */
/*   philosophers.h                                     :+:      :+:    :+:   */
/*                                                    +:+ +:+         +:+     */
/*   By: ccakir <ccakir@student.42.fr>              +#+  +:+       +#+        */
/*                                                +#+#+#+#+#+   +#+           */
/*   Created: 2026/04/24 17:47:38 by ccakir            #+#    #+#             */
/*   Updated: 2026/04/30 14:44:12 by ccakir           ###   ########.fr       */
/*                                                                            */
/* ************************************************************************** */

#ifndef PHILOSOPHERS_H
# define PHILOSOPHERS_H

# include <stdio.h>
# include <stdlib.h>
# include <pthread.h>
# include <sys/time.h>
# include <unistd.h>

typedef struct table	t_table;

typedef struct philoshopers
{
	long			last_eat_time;
	int				eat_count;
	int				id;
	pthread_mutex_t	philo_mutex;
	t_table			*table;
}				t_philo;

typedef struct table
{
	long			time_to_die;
	int				philo_count;
	int				is_someone_dead;
	int				must_eat;
	long			time_to_eat;
	long			time_to_sleep;
	long			start_time;
	pthread_t		*threads;
	pthread_mutex_t	print_mutex;
	pthread_mutex_t	dead_mutex;
	pthread_mutex_t	*forks;
	t_philo			*philos;
}				t_table;

int		init_table(t_table *table);
int		start_simulation(t_table *table);
long	get_time(void);
void	ft_usleep(long ms);
int		is_dead(t_table *table);
void	take_forks(t_philo *philo);
void	put_forks(t_philo *philo);
void	print_action(t_philo *philo, char *action);
void	eat(t_philo *philo);
void	*monitor(void *arg);
long	calc_think_time(t_philo *philo);
int		ft_atoi(const char *number);
int		check_args(char **av);

#endif